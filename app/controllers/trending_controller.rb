class TrendingController < ApplicationController
  # Public: trending is derived from public top-level hoojahs only, so no auth and
  # nothing to authorize (skip_authorization satisfies verify_authorized). Rendered
  # both lazily inside the feed's turbo_frame sidebar and as a standalone page.
  def index
    skip_authorization
    @hujahs = Hujah.trending
  end
end
