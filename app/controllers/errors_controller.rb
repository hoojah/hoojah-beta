class ErrorsController < ApplicationController
  # Rendered by config.exceptions_app (production) for unhandled 404/422/500, and
  # reachable directly at /404, /422, /500. No resource to authorize; no login.
  skip_before_action :authenticate_user!, raise: false

  # CRITICAL (security): exceptions_app redispatches the ORIGINAL request — same verb —
  # to /422 etc. The most common real 422 is InvalidAuthenticityToken (a CSRF failure).
  # Without skipping CSRF here, that request re-fails the token check a second time
  # INSIDE ShowExceptions#render_exception, whose own rescue returns Rails' bare
  # unstyled FAILSAFE_RESPONSE — defeating the branded page for the very case it exists
  # to handle. This controller only renders (no writes), so skipping forgery is safe.
  skip_before_action :verify_authenticity_token, raise: false

  def show
    skip_authorization
    @status = params[:status].to_i
    @status = 500 unless [404, 422, 500].include?(@status)
    respond_to do |format|
      format.json { render json: {error: Rack::Utils::HTTP_STATUS_CODES[@status]}, status: @status }
      format.any { render :show, status: @status, formats: [:html] }
    end
  end
end
