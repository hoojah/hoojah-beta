class DebateTurn < ApplicationRecord
  # touch: true so debates.updated_at tracks the last TURN (not just the last
  # status change) — the idle clock the timeout job reads must reflect activity,
  # else it auto-concludes actively-argued debates.
  belongs_to :debate, touch: true
  belongs_to :user

  validates :body, presence: true
end
