class BlocksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_target, only: [:create, :destroy]

  def create
    authorize Block.new(blocker: current_user, blocked: @target), :create?
    Block.transaction do
      current_user.blocks_made.find_or_create_by(blocked: @target)
      # Remove any follow in either direction. delete_all (one statement) skips
      # Follow's callbacks — wanted for the notification side effects, but NOT for the
      # accepted-only counter caches, so apply those decrements explicitly in the same
      # transaction, accepted rows only (at most 2: A→B and B→A). Pending rows move
      # nothing.
      follows = Follow.where(follower: [current_user, @target], followed: [current_user, @target])
      follows.accepted.pluck(:follower_id, :followed_id).each do |follower_id, followed_id|
        User.update_counters(followed_id, followers_count: -1)
        User.update_counters(follower_id, following_count: -1)
      end
      follows.delete_all
    end
    render_button
  rescue ActiveRecord::RecordNotUnique
    # A concurrent double-click races past find_or_create_by's SELECT — swallow it
    # so a double block stays an idempotent no-op instead of a 500.
    render_button
  end

  def destroy
    @block = current_user.blocks_made.find_by(blocked: @target)
    authorize @block, :destroy? if @block
    skip_authorization if @block.nil?
    @block&.destroy
    render_button
  end

  def index
    skip_authorization
    @blocks = current_user.blocks_made.includes(:blocked).order(created_at: :desc)
  end

  private

  def set_target = @target = User.find_by!(username: params[:username])

  def render_button
    respond_to do |f|
      f.turbo_stream # create/destroy.turbo_stream.erb both render the same replace
      f.html { redirect_to profile_path(@target.username), status: :see_other }
    end
  end
end
