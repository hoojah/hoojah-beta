class TrendingController < ApplicationController
  # Public: trending is derived from public top-level hoojahs only, so no auth and
  # nothing to authorize (skip_authorization satisfies verify_authorized). Rendered
  # both lazily inside the feed's turbo_frame sidebar and as a standalone page.
  def index
    skip_authorization
    @hujahs = Hujah.trending
    # Slice 7: keep the cache global; reject a hidden (blocked/blocked-by) author's
    # hoojahs per viewer. Signed-in only — anonymous trending is unfiltered.
    @hujahs = @hujahs.reject { |h| current_user.hidden_user_ids.include?(h.user_id) } if user_signed_in?
  end
end
