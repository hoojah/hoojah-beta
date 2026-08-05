require "rails_helper"

RSpec.describe "Trending", type: :request do
  before { Rails.cache.clear }

  it "is public (no login required) and renders" do
    hujah = create(:hujah, body: "a trending take", agree_count: 5)
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
end
