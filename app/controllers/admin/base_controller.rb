# Base for the read-only admin listings (Issue #18). Staff-gated by the headless
# AdminPolicy on `can_moderate?`. `require_staff!` authorizes exactly once per request
# (satisfying ApplicationController's verify_authorized) and denies BEFORE any record
# work — same shape as ModerationController#require_moderator!, so a non-staff member
# is turned away identically whatever the URL points at.
class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_staff!

  private

  def require_staff!
    authorize :admin, :index?
  end
end
