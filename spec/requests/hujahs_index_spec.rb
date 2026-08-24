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

  # ── Per-post visibility (2026): global feed is visible_public only ──────────────
  it "never shows a followers_only or private_only claim in the global feed" do
    author = create(:user)
    create(:hujah, user: author, visibility: :followers_only, body: "FOLLOWERS ONLY secret claim")
    create(:hujah, user: author, visibility: :private_only, body: "PRIVATE ONLY secret claim")
    create(:hujah, user: author, visibility: :visible_public, body: "PUBLIC visible claim here")
    get "/"
    expect(response.body).to include("PUBLIC visible claim here")
    expect(response.body).not_to include("FOLLOWERS ONLY secret claim")
    expect(response.body).not_to include("PRIVATE ONLY secret claim")
  end

  it "shows followers_only claims to accepted followers in the Following feed, and the viewer's own private_only claims" do
    author = create(:user)
    viewer = create(:user)
    viewer.active_follows.create!(followed: author, status: :accepted)
    create(:hujah, user: author, visibility: :followers_only, body: "FOLLOWERS ONLY for my fans")
    create(:hujah, user: viewer, visibility: :private_only, body: "MY OWN private note here")
    sign_in viewer
    get "/", params: {filter: "following"}
    expect(response.body).to include("FOLLOWERS ONLY for my fans")
    expect(response.body).to include("MY OWN private note here")
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

  # Phase 1.5 (data only — the live-debate strip UI lands in a later task): the
  # controller must preload each page's active debates in ONE bulk query, not one
  # per card, so a future per-card render of `hujah.active_debate` is N+1-free.
  it "preloads active debates for the page's hujahs in a single query" do
    hujahs = create_list(:hujah, 3, parent_id: nil)
    hujahs.each { |h| create(:debate, hujah: h, status: :active) }
    # A declined debate on its own hujah must not add a second preload query.
    create(:debate, hujah: create(:hujah, parent_id: nil), status: :declined)

    debate_selects = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      payload = ActiveSupport::Notifications::Event.new(*args).payload
      sql = payload[:sql].to_s
      debate_selects << sql if sql =~ /\ASELECT/i && sql =~ /\bdebates\b/i
    end
    get "/"
    ActiveSupport::Notifications.unsubscribe(subscriber)

    expect(response).to have_http_status(:ok)
    # One bulk `Debate.active.where(hujah_id: [...])` for the whole page — not one
    # query per card (which would scale with the number of hujahs on the page).
    expect(debate_selects.size).to eq(1)
  end
end
