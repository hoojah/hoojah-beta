class Block < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"

  validates :blocked_id, uniqueness: {scope: :blocker_id}
  validate :not_self

  private

  def not_self
    errors.add(:blocked_id, "can't block yourself") if blocker_id == blocked_id
  end
end
