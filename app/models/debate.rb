class Debate < ApplicationRecord
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

  def participant?(user) = user && [challenger_id, opponent_id].include?(user.id)

  def other(user) = (user.id == challenger_id) ? opponent : challenger

  def accept!(by:)
    return false unless pending? && by == opponent
    update!(status: :active)
    notify(challenger, :debate_your_turn)
    true
  end

  def decline!(by:)
    return false unless pending? && by == opponent
    update!(status: :declined)
    notify(challenger, :debate_declined)
    true
  end

  def post_turn(by:, body:)
    with_lock do
      return false unless active? && by == current_turn_user
      turns.create!(user: by, body: body, position: (turns.maximum(:position) || 0) + 1)
    end
    notify(other(by), :debate_your_turn)
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

  def notify_challenge = notify(opponent, :debate_challenge)

  def notify(user, category)
    Notification.create!(user:, category:, hujah_id:,
      subject_user_id: ((user == challenger) ? opponent_id : challenger_id), debate_id: id)
  end
end
