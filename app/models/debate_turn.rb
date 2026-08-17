class DebateTurn < ApplicationRecord
  # touch: true so debates.updated_at tracks the last TURN (not just the last
  # status change) — the idle clock the timeout job reads must reflect activity,
  # else it auto-concludes actively-argued debates.
  belongs_to :debate, touch: true
  belongs_to :user

  validates :body, presence: true

  # Round/phase are DERIVED, never stored. Positions are 1-based and contiguous
  # (Debate#post_turn assigns `maximum(:position) + 1` under the debate row lock,
  # backed by the unique [debate_id, position] index, and turns are only ever
  # destroyed with their debate), so each round is exactly one challenger turn
  # plus one opponent turn.
  def round = ((position - 1) / 2) + 1

  # Reads debate.rounds_limit at call time — see Debate#extendable_by? for why
  # extension is confined to the closing-round boundary, which is what keeps an
  # already-rendered label from changing under a reader.
  def phase = debate.phase_for(round)

  def phase_label = Debate::PHASE_LABELS.fetch(phase)
end
