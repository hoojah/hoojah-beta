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
    respond_to do |f|
      f.turbo_stream
      f.html { redirect_to user_followers_path(current_user.username), status: :see_other }
    end
  end

  private

  def set_target = @target = User.find_by!(username: params[:username])

  def render_button
    respond_to do |f|
      f.turbo_stream # create/destroy.turbo_stream.erb both render the same two replaces
      f.html { redirect_to profile_path(@target.username), status: :see_other }
    end
  end
end
