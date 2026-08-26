class PagesController < ApplicationController
  # Public informational pages (FAQ / Privacy / Terms). No auth: anonymous visitors
  # must be able to read them. Nothing to authorize, so skip_authorization satisfies
  # ApplicationController's after_action :verify_authorized (same shape as TrendingController).
  def faq
    skip_authorization
  end

  def privacy
    skip_authorization
  end

  def terms
    skip_authorization
  end
end
