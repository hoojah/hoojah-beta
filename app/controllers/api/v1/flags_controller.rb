class Api::V1::FlagsController < Api::V1::BaseController
  before_action :authenticate_user!

  def create
    authorize Flag
    # `.create` returns the record whether or not it persisted, so the old `if flag`
    # was always truthy: a malformed flag rendered the unpersisted record with 200 and
    # the error branch was unreachable (SECURITY-FINDINGS L1). Branch on `save` — same
    # shape Project 2 settled on in Api::V1::HujahsController#create. The success
    # response is byte-identical to before; only the failure path changed.
    flag = current_user.flags.new(flag_params)
    if flag.save
      render json: flag
    else
      render json: flag.errors, status: :unprocessable_content
    end
  end

  private

  def flag_params
    params[:flag].permit(:hujah_id, :subject)
  end
end
