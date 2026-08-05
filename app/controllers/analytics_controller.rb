class AnalyticsController < ApplicationController
  before_action :authenticate_user!

  # Owner-only by construction: UserAnalytics is scoped to current_user and there
  # is no username in the URL, so there is no other-user resource to authorize —
  # skip_authorization satisfies the app-wide verify_authorized (like #index on
  # NotificationsController). No AnalyticsPolicy: it would be tautological.
  def show
    skip_authorization
    @analytics = UserAnalytics.new(current_user)
  end
end
