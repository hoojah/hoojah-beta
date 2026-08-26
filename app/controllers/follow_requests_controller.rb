class FollowRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_follow, except: [:index]

  # Own-resource inbox (like BlocksController#index): scoped to current_user by
  # construction, so skip_authorization rather than a policy that restates it.
  def index
    skip_authorization
    @follows = current_user.passive_follows.pending
      .includes(follower: {avatar_attachment: :blob}).order(created_at: :desc)
  end

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
  # disappears. The behaviour lives on the model (Follow#dismiss_request_notification!)
  # so the accept/decline/expiry/cancel paths share one implementation.
  def dismiss_request_notification = @follow.dismiss_request_notification!
end
