class FollowPolicy < ApplicationPolicy
  def create? = user.present?

  def destroy? = user.present? && record.follower_id == user.id
end
