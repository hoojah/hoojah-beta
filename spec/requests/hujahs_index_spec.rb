require "rails_helper"

RSpec.describe "Hujahs index", type: :request do
  it "lists top-level hujahs and paginates via turbo_stream" do
    user = create(:user)
    create_list(:hujah, 20, user: user, parent_id: nil)
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body.scan('data-testid="hujah-card"').size).to eq(15)

    get "/", params: {page: 2}, headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('turbo-stream action="append"')
  end

  it "shows the Login control to logged-out visitors" do
    get "/"
    expect(response.body).to include("Login")
  end

  it "shows the logout control to signed-in users" do
    sign_in create(:user)
    get "/"
    expect(response.body).to include("Log Out")
  end

  # Double-submit guard: paginated turbo_stream appends must never re-emit a card
  # already shown, so a stray second "Load more" can't duplicate DOM ids. Page 2 is
  # also deterministic across repeated fetches.
  it "never emits duplicate card dom_ids across paginated appends" do
    user = create(:user)
    create_list(:hujah, 20, user: user, parent_id: nil)

    get "/"
    page1_ids = response.body.scan(/id="(vote_bars_hujah_\d+)"/).flatten
    expect(page1_ids.size).to eq(15)

    get "/", params: {page: 2}, headers: {"Accept" => "text/vnd.turbo-stream.html"}
    page2_ids = response.body.scan(/id="(vote_bars_hujah_\d+)"/).flatten

    # Re-fetching page 2 yields the same 5 cards (stable pagination).
    get "/", params: {page: 2}, headers: {"Accept" => "text/vnd.turbo-stream.html"}
    page2_again_ids = response.body.scan(/id="(vote_bars_hujah_\d+)"/).flatten
    expect(page2_again_ids).to eq(page2_ids)

    combined = page1_ids + page2_ids
    expect(combined.uniq).to eq(combined)
    expect(page2_ids.size).to eq(5)
  end
end
