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

  # Phase 2.5: the standalone page gets the rich, ranked cards from the 2026 mockup.
  # `Hujah.trending` is the single source of the set/order — the request must not
  # add a second query or filter on top of it.
  describe "the full page (not the sidebar frame)" do
    it "renders a rank-1 gradient hero and rounded-2xl cards for the rest, in Hujah.trending's order" do
      top = create(:hujah, body: "Malaysia should adopt a 4-day work week nationwide.",
        agree_count: 8000, neutral_count: 100, disagree_count: 104) # 8204 votes
      second = create(:hujah, body: "Public transport should be completely free by 2030.",
        agree_count: 200, neutral_count: 30, disagree_count: 27) # 257 votes, lower gravity score

      # This is the set/order the page must render — Hujah.trending itself, not a
      # second query. Both examples below assert against it, not against the
      # fixtures' creation order.
      expect(Hujah.trending.to_a).to eq([top, second])

      get "/trending"

      expect(response.body).to include('data-testid="trending-hero"')
      expect(response.body).to include('class="rounded-3xl')
      expect(response.body).to include("Malaysia should adopt a 4-day work week nationwide.")
      expect(response.body).to include("8204 votes")

      expect(response.body).to include('data-testid="trending-rank-card"')
      expect(response.body).to include("Public transport should be completely free by 2030.")
      expect(response.body).to include("257 votes")

      # rank-1 body appears before rank-2 body — proves order is preserved, not re-sorted.
      expect(response.body.index(top.body)).to be < response.body.index(second.body)
    end

    it "does not invent a period toggle or a %-delta" do
      create(:hujah, body: "a trending take", agree_count: 5)
      get "/trending"
      expect(response.body).not_to include('data-testid="trending-delta"')
      expect(response.body).not_to include('data-testid="period-toggle"')
    end

    it "renders the empty state when nothing is trending" do
      get "/trending"
      expect(response.body).to include("Nothing trending yet.")
    end
  end

  # The feed's lazy sidebar (`turbo_frame_tag "trending", src: trending_path,
  # loading: :lazy`) issues a real Turbo Frame request, which Turbo tags with a
  # `Turbo-Frame` request header carrying the frame's id. That's the load-bearing
  # signal this spec drives directly (system spec covers the real lazy-load path).
  describe "the sidebar's lazy turbo frame request" do
    it "still renders the minimal _trending list, not the rich cards" do
      create(:hujah, body: "a hot trending take", agree_count: 25)
      get "/trending", headers: {"Turbo-Frame" => "trending"}

      expect(response.body).to include("a hot trending take")
      expect(response.body).not_to include('data-testid="trending-hero"')
      expect(response.body).not_to include('data-testid="trending-rank-card"')
    end
  end
end
