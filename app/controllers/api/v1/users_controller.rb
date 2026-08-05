class Api::V1::UsersController < Api::V1::BaseController
  before_action :authenticate_user!, only: :update

  def show
    if user
      render json: UserSerializer.new(user).serializable_hash
    end
  end

  def update
    if current_user.update(user_params)
      render json: UserSerializer.new(user).serializable_hash
    else
      render json: user.errors
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
