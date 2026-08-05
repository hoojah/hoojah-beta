class Api::V1::UsersController < Api::V1::BaseController
  before_action :authenticate_user!, only: :update

  def show
    skip_authorization
    # Slice 7b (Gate 11, A-1): a private account's profile is not readable via the JSON
    # endpoint by a non-follower. The gated HTML profile (name/@handle/counts) is not
    # mirrored here yet — native parity is deferred to Project 3.
    if user&.visible_to?(current_user)
      render json: UserSerializer.new(user).serializable_hash
    else
      head :not_found
    end
  end

  def update
    @user = current_user
    authorize @user
    if @user.update(user_params)
      render json: UserSerializer.new(@user).serializable_hash
    else
      render json: @user.errors
    end
  end

  private

  def user_params
    params.permit(:full_name, :username, :email, :photo, :location, :headline, :link)
  end

  def user
    @user ||= User.find_by_username(params[:username])
  end
end
