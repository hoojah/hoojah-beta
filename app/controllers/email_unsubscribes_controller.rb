class EmailUnsubscribesController < ApplicationController
  # Public by design: the signed token in the URL is the credential, so there is no
  # login (ApplicationController has no global authenticate_user!, nothing to skip).
  # Pundit has no record to authorize, hence skip_authorization in each action.
  #
  # CSRF exception: RFC 8058 one-click unsubscribe is a POST made by the MAIL PROVIDER,
  # not a browser, so it cannot carry a CSRF token. CLAUDE.md says HTML writes keep
  # CSRF; this is the one deliberate exception. It is safe because the request is
  # authenticated by the signed token (unforgeable, scoped to this purpose and this
  # email address) and the only effect is switching the user's own mail off.
  skip_forgery_protection only: :create

  before_action :set_user

  def show
    skip_authorization
  end

  # Idempotent. The provider's one-click POST (body `List-Unsubscribe=One-Click`) gets a
  # bare 200. Every other POST is the browser form and redirects back to the show page,
  # which reports "off" — a redirect because Turbo rejects a 200 form response.
  # The branch is on the param ALONE, never on request.format: Turbo's button_to sends
  # Accept "text/vnd.turbo-stream.html, text/html, ..." (no */*), which Rails resolves to
  # turbo_stream, so a format check would hand Turbo a 200 and the page would never update.
  def create
    skip_authorization
    # update_attribute, not update!: it skips validations (callbacks still run). A
    # legacy/OAuth user with stale data (blank full_name, bad link, avatar) would
    # otherwise 500 here — including on the provider's one-click POST — and an
    # unsubscribe must never fail because of unrelated profile validity.
    @user.update_attribute(:email_notifications, false) if @user.email_notifications?
    if params["List-Unsubscribe"] == "One-Click"
      head :ok
    else
      redirect_to email_unsubscribe_path(params[:token]), status: :see_other
    end
  end

  private

  # Same answer for a bad, tampered or stale token (including one invalidated by an
  # email change) so nothing reveals whether an account exists.
  def set_user
    @user = User.find_by_token_for(:email_unsubscribe, params[:token])
    return if @user
    skip_authorization
    respond_to do |format|
      format.html { render :invalid, status: :not_found }
      # Turbo form submits ask for turbo_stream; without this branch they would fall to
      # format.any and the user would see nothing. Render the same HTML page for them.
      format.turbo_stream { render :invalid, formats: [:html], status: :not_found }
      format.any { head :not_found }
    end
  end
end
