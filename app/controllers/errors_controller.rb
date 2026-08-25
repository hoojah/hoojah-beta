class ErrorsController < ApplicationController
  # Rendered by config.exceptions_app (production) for unhandled 404/422/500 — the
  # real path: ShowExceptions redispatches the failed request straight to this Rack
  # endpoint (bypassing ActionDispatch::Static), so it runs for genuine errors and
  # honours the original Accept header. A directly-typed GET /404 in production is a
  # different story: ActionDispatch::Static sits ahead of routing and serves the
  # (branded) public/404.html at 200 before the router is reached — so the /404,/422,
  # /500 routes below are for the exceptions_app dispatch and for tests (which disable
  # static serving), NOT a promise that typing the URL hits this controller in prod.
  # No resource to authorize; no login.
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
