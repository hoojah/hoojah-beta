class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  validates :followed_id, uniqueness: {scope: :follower_id}
  validate :not_self

  after_create_commit :notify_followed
  after_create_commit :award_first_follower

  private

  def not_self
    errors.add(:followed_id, "can't follow yourself") if follower_id == followed_id
  end

  def notify_followed
    Notification.create!(user_id: followed_id, category: :new_follower, subject_user_id: follower_id)
  end

  def award_first_follower
    UserBadge.award(followed, "first_follower")
  end
end
