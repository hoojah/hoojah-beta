class Api::V1::UsersController < ApplicationController
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
    params.permit(:username, :full_name, :location, :link, :photo, :headline, :id, :user)
  end

  def user
    @user ||= User.find_by_username(params[:username])
  end
end
