# Admin all-hoojahs listing (Issue #18). Read-only. Newest first.
class Admin::HujahsController < Admin::BaseController
  def index
    # Deliberately NOT `not_removed`-swept and NOT `visible_to`-filtered: staff are the
    # audience that reads removed AND non-public (followers_only / private_only) content
    # — the same rationale as the moderation queue. includes(:user) avoids the author
    # N+1 in the row.
    @pagy, @hujahs = pagy(:countless, Hujah.order(created_at: :desc).includes(:user), limit: 25)
  end
end
