class BlocksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_target, only: [:create, :destroy]

  def create
    authorize Block.new(blocker: current_user, blocked: @target), :create?
    Block.transaction do
      current_user.blocks_made.find_or_create_by(blocked: @target)
      # Remove any follow in either direction — Follow has no destroy callbacks, so
      # delete_all (one statement) is safe and skips the notification side effects.
      Follow.where(follower: [current_user, @target], followed: [current_user, @target]).delete_all
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
