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
  #
  # Turbo: capture the dismissed notification ids BEFORE rendering so the stream
  # (_actioned.turbo_stream.erb) can remove their cards. HTML fallback (no-JS)
  # keeps the redirect_back. One stream body serves both the inbox and the
  # notifications page — turbo_stream.remove of an absent target is a no-op.
  def update
    authorize @follow, :update?, policy_class: FollowRequestPolicy
    @follow.update!(status: :accepted)
    @dismissed_notification_ids = @follow.dismiss_request_notification!.map(&:id)
    respond_to do |f|
      f.turbo_stream
      f.html { redirect_back fallback_location: notifications_path, status: :see_other }
    end
  end

  # Decline: drop the pending follow outright (no notification blast). Dismiss the
  # request notification FIRST (its query keys on the follower/followed id pair, not
  # the follow's own id, so it works after destroy too — but capturing the ids up
  # front is clearest), then destroy. `@follow` survives in memory after destroy,
  # so `dom_id(@follow, :request)` still resolves in the stream.
  def destroy
    authorize @follow, :destroy?, policy_class: FollowRequestPolicy
    @dismissed_notification_ids = @follow.dismiss_request_notification!.map(&:id)
    @follow.destroy
    respond_to do |f|
      f.turbo_stream
      f.html { redirect_back fallback_location: notifications_path, status: :see_other }
    end
  end

  private

  def set_follow = @follow = Follow.find(params[:id])
end
