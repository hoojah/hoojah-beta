class Debate < ApplicationRecord
  PHASE_LABELS = {opening: "Opening statement", counter: "Counter-argument",
                  response: "Response", closing: "Closing statement"}.freeze
  MAX_ROUNDS = 10

  extend FriendlyId

  friendly_id :slug_source, use: :slugged

  belongs_to :hujah
  belongs_to :challenger, class_name: "User"
  belongs_to :opponent, class_name: "User"
  has_many :turns, class_name: "DebateTurn", dependent: :destroy
  has_many :debate_verdicts, dependent: :destroy

  enum :status, {pending: 0, active: 1, concluded: 2, declined: 3}, default: :pending

  validates :challenger_stance, :opponent_stance, presence: true
  validate { errors.add(:opponent_stance, "must oppose") if challenger_stance == opponent_stance }
  validate { errors.add(:opponent_id, "must differ") if challenger_id == opponent_id }

  after_create_commit :notify_challenge

  def slug_source = ActionController::Base.helpers.strip_tags(hujah.body.to_s).split.first(8).join(" ")

  # Derived — no column. nil unless active; challenger moves first (no turns yet),
  # else whichever participant did NOT author the last turn.
  def current_turn_user
    return nil unless active?
    last = turns.order(:position).last
    if last.nil?
      challenger
    else
      ((last.user_id == challenger_id) ? opponent : challenger)
    end
  end

  def current_round = (turns.count / 2) + 1

  # Pure derivation — nothing is stored on debate_turns.
  def phase_for(round)
    return :opening if round == 1
    return :closing if round == rounds_limit
    round.even? ? :counter : :response
  end

  # The position of the last turn this debate can hold. `>=` (not `==`) is used
  # against it in post_turn so the cap is a floor, not an exact hit: a debate
  # whose rounds_limit were ever lowered, or whose positions had somehow skipped,
  # would step OVER an equality check and run unbounded.
  def final_position = rounds_limit * 2

  # Only at the closing-round BOUNDARY: the round has been reached but holds no
  # turn yet. Extending once a closing turn exists would silently relabel it from
  # CLOSING to COUNTER, because phase is derived at render time.
  #
  # `turns.count` and `turns.maximum(:position)` are interchangeable here —
  # positions are contiguous from 1 (assigned as maximum + 1 under the debate row
  # lock, unique index on [debate_id, position], no per-turn delete path) — but
  # count states the intent ("both halves of the previous round are in") directly.
  def extendable_by?(user)
    active? && participant?(user) && rounds_limit < MAX_ROUNDS &&
      turns.count == (rounds_limit - 1) * 2
  end

  # Unilateral by design: the window belongs to whoever moves first in the closing
  # round, and the other participant retains conclude! throughout — so no
  # negotiation state is needed.
  def extend_rounds!(by:)
    return false unless extendable_by?(by)
    update!(rounds_limit: rounds_limit + 1)
    broadcast_state_change
    true
  end

  def participant?(user) = user && [challenger_id, opponent_id].include?(user.id)

  def other(user) = (user.id == challenger_id) ? opponent : challenger

  def accept!(by:)
    return false unless pending? && by == opponent
    update!(status: :active)
    notify(challenger, :debate_your_turn)
    broadcast_state_change
    true
  end

  def decline!(by:)
    return false unless pending? && by == opponent
    update!(status: :declined)
    notify(challenger, :debate_declined)
    true
  end

  def post_turn(by:, body:)
    turn = nil
    with_lock do
      return false unless active? && by == current_turn_user
      turn = turns.create!(user: by, body: body, position: (turns.maximum(:position) || 0) + 1)
    end
    # The closing turn ends the debate, so there is no next mover to summon.
    capped = turn.position >= final_position
    if capped
      # Conclude BEFORE enqueuing any broadcast, and deliberately OUTSIDE the
      # with_lock block above.
      #
      # Outside the lock because conclude! calls UserBadge.award, which rescues
      # RecordNotUnique — doing that inside an open Postgres transaction would
      # poison it and lose the turn we just wrote (see UserBadge.award's note).
      # The lock has already committed here, so conclude!'s own update! takes a
      # fresh transaction and cannot self-deadlock.
      #
      # Before the broadcasts because every *_later_to renders in a job, from a
      # GlobalID-reloaded record, at execution time — not from the state at
      # enqueue time. If the composer job ran while the debate were still
      # `active`, it would paint the turn form for the opponent, and
      # conclude!'s broadcast_state_change (status + actions only) would never
      # correct it. Concluding first makes every render observe the final state.
      conclude!(by: nil)
    else
      notify(other(by), :debate_your_turn)
    end
    # Real-time: append the new turn to everyone on the debate stream, then refresh
    # each participant's own composer (the mover flips to "waiting", the other to
    # the turn form — or both to "concluded" on the capping turn) on their
    # user-signed stream.
    broadcast_append_later_to self, target: dom_id(self, :transcript),
      partial: "debates/debate_turn", locals: {debate_turn: turn}
    broadcast_to_each_participant(target: :composer, partial: "debates/turn_composer")
    true
  end

  # by: nil is the SYSTEM/timeout path (ConcludeStaleDebatesJob) — there is no
  # actor to exclude, so BOTH participants are notified. A manual conclude always
  # passes current_user (never nil), so notify(other(by)) is only reached there.
  def conclude!(by: nil)
    return false unless active?
    return false unless by.nil? || participant?(by)
    update!(status: :concluded)
    if by.nil?
      notify(challenger, :debate_concluded)
      notify(opponent, :debate_concluded)
    else
      notify(other(by), :debate_concluded)
    end
    # After the status update commits — both participants earn first_debate.
    UserBadge.award(challenger, "first_debate")
    UserBadge.award(opponent, "first_debate")
    broadcast_state_change
    true
  end

  # Spectator verdict — a single insert with a METHOD-LEVEL rescue (no
  # transaction, no counters: the tally is compute-on-read, so there is nothing
  # to poison). Immutable one-vote-per-spectator; a second vote races the DB
  # unique index and is swallowed as an idempotent no-op.
  def cast_verdict(by:, choice:)
    return false unless concluded? && !participant?(by) && DebateVerdict.choices.key?(choice.to_s)
    debate_verdicts.create!(user: by, choice: choice)
    true
  rescue ActiveRecord::RecordNotUnique
    false # already voted — idempotent no-op
  end

  # Compute-on-read tally (renders on one page, not a list). No denormalized
  # columns on debates.
  def verdict_tally = debate_verdicts.group(:choice).count

  private

  # accept!/conclude! share this: the status label is viewer-agnostic (broadcast to
  # the whole debate), while the accept/decline/conclude affordances are viewer-scoped
  # (each participant gets their own on their user-signed stream).
  def broadcast_state_change
    broadcast_replace_later_to self, target: dom_id(self, :status),
      partial: "debates/debate_status", locals: {debate: self}
    broadcast_to_each_participant(target: :actions, partial: "debates/debate_actions")
  end

  # Replace a viewer-scoped region for each participant on their own user-signed
  # `[self, participant]` stream — the single home for the "each participant sees
  # their own render" broadcast intent (composer on post_turn, actions on state change).
  def broadcast_to_each_participant(target:, partial:)
    [challenger, opponent].each do |p|
      broadcast_replace_later_to [self, p], target: dom_id(self, target),
        partial: partial, locals: {debate: self, viewer: p}
    end
  end

  # `dom_id` isn't an instance method on models; delegate to the canonical helper so
  # the broadcast targets match the view's `dom_id(@debate, :status)` etc.
  def dom_id(...) = ActionView::RecordIdentifier.dom_id(...)

  def notify_challenge = notify(opponent, :debate_challenge)

  def notify(user, category)
    Notification.create!(user:, category:, hujah_id:,
      subject_user_id: ((user == challenger) ? opponent_id : challenger_id), debate_id: id)
  end
end
