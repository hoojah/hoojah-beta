# Admin all-users listing (Issue #18). Read-only. Newest first.
class Admin::UsersController < Admin::BaseController
  def index
    # No visibility scoping: staff deliberately see private accounts too — the whole
    # point of the listing. .with_attached_avatar preloads the ActiveStorage blob so
    # the per-row avatar does not N+1.
    @pagy, @users = pagy(:countless, User.order(created_at: :desc).with_attached_avatar, limit: 25)
  end
end
