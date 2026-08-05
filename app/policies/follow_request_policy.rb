# Only the followed user (the request's target) may accept or decline a pending
# follow request. A requester or any third party is denied (Pundit rescue → 403).
class FollowRequestPolicy < ApplicationPolicy
  def update? = user.present? && record.followed_id == user.id

  def destroy? = update?
end
