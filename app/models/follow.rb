class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  # A follow of a private user starts `pending` (request→approve); a follow of a
  # public user is set `accepted` by the controller. The DB default is pending
  # (security-conservative: a forgotten status is inert, never a leak).
  enum :status, {pending: 0, accepted: 1}

  validates :followed_id, uniqueness: {scope: :follower_id}
  validate :not_self

  # ALL follow notifications/badges live here, gated on ACCEPTED. An accepted follow
  # (public target) fires new_follower + the first_follower badge; a pending follow
  # (private target) fires only a follow_request to the target — NEVER new_follower or
  # the badge (the v1 bug: the badge/notification used to fire on the request itself).
  after_create_commit :notify_new_follow
  # Accepting a request (pending -> accepted) tells the requester + belatedly runs the
  # new_follower + first_follower side effects that were withheld while pending.
  after_update_commit :notify_accepted, if: -> { saved_change_to_status? && accepted? }

  private

  def not_self
    errors.add(:followed_id, "can't follow yourself") if follower_id == followed_id
  end

  def notify_new_follow
    if accepted?
      notify_followed
      award_first_follower
    else
      Notification.create!(user_id: followed_id, category: :follow_request, subject_user_id: follower_id)
    end
  end

  def notify_accepted
    Notification.create!(user_id: follower_id, category: :follow_accepted, subject_user_id: followed_id)
    notify_followed
    award_first_follower
  end

  def notify_followed
    Notification.create!(user_id: followed_id, category: :new_follower, subject_user_id: follower_id)
  end

  def award_first_follower
    UserBadge.award(followed, "first_follower")
  end
end
