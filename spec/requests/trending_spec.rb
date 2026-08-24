require "rails_helper"

RSpec.describe "Trending", type: :request do
  before { Rails.cache.clear }

  it "is public (no login required) and renders" do
    create(:hujah, body: "a trending take", agree_count: 5)
    get "/trending"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Trending")
    expect(response.body).to include("a trending take")
  end

  it "renders the empty state when nothing is trending" do
    get "/trending"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nothing trending yet.")
  end

  # Per-post visibility (2026): a non-public claim with activity must never surface
  # on public /trending, even from a public author.
  it "never surfaces a followers_only claim on trending" do
    author = create(:user)
    create(:hujah, user: author, visibility: :followers_only, body: "FOLLOWERS ONLY trending bait", agree_count: 50)
    get "/trending"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("FOLLOWERS ONLY trending bait")
  end
end
