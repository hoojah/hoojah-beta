class Api::V1::FlagsController < Api::V1::BaseController
  before_action :authenticate_user!

  # Slice 11 (A2): `flag_params` uses `require`, so a POST with no `flag` key raises
  # ParameterMissing. Production maps that to 400 via `rescue_responses`, but the app
  # runs `show_exceptions=:none` in test so the raise propagates — rescue here to
  # return the 400 the request spec asserts (same in-controller-rescue pattern as
  # HujahsController#create). Fires before `authorize`, but a missing param is a
  # client error regardless of who sends it.
  rescue_from ActionController::ParameterMissing do |e|
    render json: {error: e.message}, status: :bad_request
  end

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
    # Slice 11 (A2): `require` so a POST with no `flag` key returns 400 (Rails maps
    # ParameterMissing → :bad_request) instead of a NoMethodError-on-nil 500 that fired
    # BEFORE `authorize`. Breaking change accepted 2026-08-19 (no legacy native client
    # hits Api::V1); the HTML FlagsController already uses `require`.
    params.require(:flag).permit(:hujah_id, :subject)
  end
end
