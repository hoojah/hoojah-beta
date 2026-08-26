class FollowPolicy < ApplicationPolicy
  # Reject a follow of a hidden (blocked/blocked-by) user — Slice 7.
  def create? = user.present? && !user.hidden_user_ids.include?(record.followed_id)

  def destroy? = user.present? && record.follower_id == user.id

  # Only the followed user may remove a follower (the mirror of destroy?, which is
  # follower-only). record is the accepted Follow row being severed.
  def remove_follower? = user.present? && record.followed_id == user.id
end
