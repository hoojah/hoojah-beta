class UsersController < ApplicationController
  before_action :authenticate_user!, only: [:edit, :update]
  before_action :set_user

  def show
    skip_authorization
    # Eager-load the poster on each hoojah so the profile list avoids an N+1.
    @hujahs = @user.hujahs.includes(:user).order(updated_at: :desc)
  end

  # Public follower / following lists. Follows are public, so no policy scoping —
  # skip_authorization (else verify_authorized 500s).
  def followers
    skip_authorization
    @users = @user.followers.order(:username)
  end

  def following
    skip_authorization
    @users = @user.following.order(:username)
  end

  def edit
    authorize @user
  end

  def update
    authorize @user
    if @user.update(user_params)
      respond_to do |format|
        format.turbo_stream # update.turbo_stream.erb — refresh header + close_dialog
        format.html { redirect_to profile_path(@user.username), status: :see_other }
      end
    else
      # Re-render the form as HTML for every request format (there is no
      # edit.turbo_stream variant) so a failed Turbo-Stream submit still 422s.
      render :edit, status: :unprocessable_content, formats: [:html]
    end
  end

  private

  # Look up by username (the public identifier). Missing → 404.
  def set_user
    @user = User.find_by!(username: params[:username])
  end

  # Email stays API-only (the HTML edit form omits it, matching the legacy SPA).
  def user_params
    params.require(:user).permit(:full_name, :username, :location, :link, :headline, :photo)
  end
end
