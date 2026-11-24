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

  # Idempotent. The provider's one-click POST (body `List-Unsubscribe=One-Click`, or any
  # non-HTML request) gets a bare 200. The browser form POST redirects back to the
  # show page, which reports "off" — a redirect because Turbo rejects a 200 form response.
  def create
    skip_authorization
    @user.update!(email_notifications: false) if @user.email_notifications?
    if request.format.html? && params["List-Unsubscribe"] != "One-Click"
      redirect_to email_unsubscribe_path(params[:token]), status: :see_other
    else
      head :ok
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
      format.any { head :not_found }
    end
  end
end
