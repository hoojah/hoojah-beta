class Api::V1::FlagsController < Api::V1::BaseController
  before_action :authenticate_user!

  def create
    authorize Flag
    flag = current_user.flags.create(flag_params)
    if flag
      render json: flag
    else
      render json: flag.errors
    end
  end

  private

  def flag_params
    params[:flag].permit(:hujah_id, :subject)
  end
end
