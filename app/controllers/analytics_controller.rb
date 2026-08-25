class AnalyticsController < ApplicationController
  before_action :authenticate_user!

  # Owner-only by construction: UserAnalytics is scoped to current_user and there
  # is no username in the URL, so there is no other-user resource to authorize —
  # skip_authorization satisfies the app-wide verify_authorized (like #index on
  # NotificationsController). No AnalyticsPolicy: it would be tautological.
  def show
    skip_authorization
    @analytics = UserAnalytics.new(current_user)

    # Followers KPI (Slice 2026 Phase 4.6). Deliberately NOT on UserAnalytics: its
    # header comment forbids that object from ever touching `users`, so a follower
    # count is computed here instead, off `User#followers` (accepted-only,
    # `app/models/user.rb`). This is a single extra COUNT query, not a join folded
    # into any UserAnalytics aggregate, so the vote-privacy provenance test (which
    # only inspects UserAnalytics' own queries) is untouched by this line.
    @followers_count = current_user.followers.count
  end
end
