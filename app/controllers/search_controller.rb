class SearchController < ApplicationController
  # Public, read-only — no owner to authorize (skip_authorization satisfies
  # ApplicationController's verify_authorized). Every result set is filtered
  # through Hujah.visible_to / User.visible_to (see those scopes), so a search
  # result can never leak content a normal feed/profile visit wouldn't show.
  def index
    skip_authorization
    @query = params[:q].to_s.strip
    if @query.present?
      @hujahs = Hujah.search(@query, viewer: current_user)
      @users = User.search(@query, viewer: current_user)
      @hashtags = Hashtag.search(@query)
    end
    # Browse state (blank query): trending tags, independent of @query.
    @browse_hashtags = Hashtag.order(hujahs_count: :desc).limit(20)
  end
end
