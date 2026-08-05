class FollowRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_follow

  # Accept a pending follow request. Only the followed user may act
  # (FollowRequestPolicy). Flipping status → accepted fires the Follow model's
  # after_update_commit (follow_accepted to the requester + new_follower + badge).
  def update
    authorize @follow, :update?, policy_class: FollowRequestPolicy
    @follow.update!(status: :accepted)
    dismiss_request_notification
    redirect_back fallback_location: notifications_path, status: :see_other
  end

  # Decline: drop the pending follow outright (no notification blast).
  def destroy
    authorize @follow, :destroy?, policy_class: FollowRequestPolicy
    @follow.destroy
    dismiss_request_notification
    redirect_back fallback_location: notifications_path, status: :see_other
  end

  private

  def set_follow = @follow = Follow.find(params[:id])

  # The follow_request notification has been actioned — remove it so its card
  # disappears (requests are managed from the card; the inbox page is deferred).
  def dismiss_request_notification
    Notification.where(user_id: @follow.followed_id, subject_user_id: @follow.follower_id,
      category: :follow_request).destroy_all
  end
end
