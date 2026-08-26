class FollowsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_target

  def create
    authorize Follow.new(follower: current_user, followed: @target), :create?
    # The enum default is `pending` (a forgotten status is inert, never a leak), so
    # set the status EXPLICITLY: a private target starts a request, a public target
    # is followed outright. find_or_initialize_by keeps a re-follow idempotent.
    follow = current_user.active_follows.find_or_initialize_by(followed: @target)
    follow.status = @target.private? ? :pending : :accepted if follow.new_record?
    follow.save
    render_button
  rescue ActiveRecord::RecordNotUnique
    # A concurrent double-click races past find_or_create_by's SELECT and both
    # INSERTs hit the unique index — swallow it so the follow stays an idempotent
    # no-op instead of a 500.
    render_button
  end

  def destroy
    @follow = current_user.active_follows.find_by(followed: @target)
    authorize @follow, :destroy? if @follow
    skip_authorization if @follow.nil?
    # A cancelled REQUEST must clear the target's follow_request card (the same
    # dismissal accept/decline perform) - else it offers dead buttons forever. An
    # unfollow of an ACCEPTED row has no such card, so this is pending-only. Read
    # the status BEFORE destroy, while the row still exists.
    @follow.dismiss_request_notification! if @follow&.pending?
    @follow&.destroy
    render_button
  end

  # Sever an accepted follow pointed at me. @target (set_target, :username) is the
  # FOLLOWER being removed. Scoped .accepted: a pending request is not a follower —
  # it is declined via follow_requests#destroy, and removing it here would skip the
  # request-notification dismissal that path owns.
  def remove_follower
    @follow = current_user.passive_follows.accepted.find_by(follower: @target)
    authorize @follow, :remove_follower? if @follow
    skip_authorization if @follow.nil?
    @follow&.destroy # accepted → Follow's after_destroy decrements both counters
    # The chip reads current_user.followers_count (denormalized column). The
    # decrement above went through User.update_counters — atomic SQL that never
    # syncs the in-memory record — so reload before the stream renders the count.
    current_user.reload
    respond_to do |f|
      f.turbo_stream
      f.html { redirect_to user_followers_path(current_user.username), status: :see_other }
    end
  end

  private

  def set_target = @target = User.find_by!(username: params[:username])

  def render_button
    # The follower-count chip reads @target.followers_count (denormalized column,
    # gap 8 read-flip). Follow's create/destroy callbacks maintain it via
    # User.update_counters — atomic SQL that leaves the in-memory @target stale — so
    # reload it here before the Turbo Stream re-renders the chip.
    @target.reload
    respond_to do |f|
      f.turbo_stream # create/destroy.turbo_stream.erb both render the same two replaces
      f.html { redirect_to profile_path(@target.username), status: :see_other }
    end
  end
end
