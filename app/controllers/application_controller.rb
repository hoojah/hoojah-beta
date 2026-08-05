class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # CSRF is ON (Devise + Turbo). Api::V1::BaseController overrides the strategy for JSON clients.

  # Pagy ~> 43.6 exposes the `pagy(:countless, collection)` paginator via this mixin
  # (the reworked replacement for the classic `Pagy::Backend`).
  include Pagy::Method

  # All-or-nothing authorization: every non-Devise action must call `authorize`
  # or `skip_authorization` exactly once. Devise controllers are exempt so
  # login/signup/logout/password/account-update keep working.
  after_action :verify_authorized, unless: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def user_not_authorized
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, alert: "Not allowed." }
      format.any { head :forbidden }
    end
  end
end
