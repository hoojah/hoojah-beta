require "rails_helper"

# Phase 2.2/2.3 — full-text search. SECURITY-CRITICAL: search MUST filter through
# the same `visible_to` scopes as the rest of the app (Hujah, User), so a search
# result can never leak content a normal feed/profile visit wouldn't show. Every
# gate here has a matching gate already proven for the feed/profile in
# private_visibility_spec.rb and block_visibility_spec.rb — this file re-proves
# them specifically for the search surface.
RSpec.describe "Search", type: :request do
  # current_user is loaded fresh per-request in production; Devise's request-spec
  # sign_in reuses the passed object, which can carry a stale memoized
  # hidden_user_ids (see block_visibility_spec's comment). Sign in a freshly
  # loaded record so the block gate is faithfully modeled.
  def sign_in_fresh(user) = sign_in(User.find(user.id))

  describe "GET /search" do
    it "is public: works signed out and returns 200" do
      get "/search"
      expect(response).to have_http_status(:ok)
    end

    it "renders the browse state when q is blank" do
      Hashtag.create!(name: "browsetag", display: "BrowseTag")
      get "/search"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("BrowseTag")
    end
  end

  describe "GET /search?q=... — hujah visibility leaks" do
    let!(:owner) { create(:user, username: "sowner", private: false) }
    let!(:follower) { create(:user, username: "sfollower") }
    let!(:stranger) { create(:user, username: "sstranger") }

    before { follower.active_follows.create!(followed: owner, status: :accepted) }

    it "excludes a followers_only hoojah from an anonymous viewer and a non-follower, includes it for a follower/owner" do
      hidden = create(:hujah, user: owner, visibility: :followers_only,
        body: "SEARCHLEAK followers only content here")

      get "/search", params: {q: "SEARCHLEAK"}
      expect(response.body).not_to include(hidden.slug)

      sign_in_fresh stranger
      get "/search", params: {q: "SEARCHLEAK"}
      expect(response.body).not_to include(hidden.slug)

      sign_in_fresh follower
      get "/search", params: {q: "SEARCHLEAK"}
      expect(response.body).to include(hidden.slug)

      sign_in_fresh owner
      get "/search", params: {q: "SEARCHLEAK"}
      expect(response.body).to include(hidden.slug)
    end

    it "excludes a private_only hoojah from everyone but the owner" do
      hidden = create(:hujah, user: owner, visibility: :private_only,
        body: "SEARCHPRIVATE only-me content here")

      get "/search", params: {q: "SEARCHPRIVATE"}
      expect(response.body).not_to include(hidden.slug)

      sign_in_fresh follower
      get "/search", params: {q: "SEARCHPRIVATE"}
      expect(response.body).not_to include(hidden.slug)

      sign_in_fresh owner
      get "/search", params: {q: "SEARCHPRIVATE"}
      expect(response.body).to include(hidden.slug)
    end

    it "excludes a private-account author's hoojah from a non-follower/anon, includes it for an accepted follower" do
      private_author = create(:user, username: "sprivateauthor", private: true)
      follower.active_follows.create!(followed: private_author, status: :accepted)
      hidden = create(:hujah, user: private_author, visibility: :visible_public,
        body: "SEARCHPRIVACCT content from a locked account")

      get "/search", params: {q: "SEARCHPRIVACCT"}
      expect(response.body).not_to include(hidden.slug)

      sign_in_fresh stranger
      get "/search", params: {q: "SEARCHPRIVACCT"}
      expect(response.body).not_to include(hidden.slug)

      sign_in_fresh follower
      get "/search", params: {q: "SEARCHPRIVACCT"}
      expect(response.body).to include(hidden.slug)
    end

    it "never returns a reply (parent_id present) in hujah results even when its body matches" do
      parent = create(:hujah, user: owner, body: "a parent claim about something else")
      reply = create(:hujah, parent: parent, user: owner, body: "SEARCHREPLY only in a reply body")

      sign_in_fresh owner
      get "/search", params: {q: "SEARCHREPLY"}
      expect(response.body).not_to include(reply.slug)
    end
  end

  describe "GET /search?q=... — user visibility leaks" do
    it "excludes a private account from search results for a non-follower/anon, includes it for an accepted follower" do
      private_user = create(:user, username: "hiddenprivateperson", private: true)
      follower = create(:user, username: "hpfollower")
      stranger = create(:user, username: "hpstranger")
      follower.active_follows.create!(followed: private_user, status: :accepted)

      # `@` prefix distinguishes a rendered result-list entry from the query text
      # merely echoed back into the search box's `value=` attribute.
      get "/search", params: {q: "hiddenprivateperson"}
      expect(response.body).not_to include("@hiddenprivateperson")

      sign_in_fresh stranger
      get "/search", params: {q: "hiddenprivateperson"}
      expect(response.body).not_to include("@hiddenprivateperson")

      sign_in_fresh follower
      get "/search", params: {q: "hiddenprivateperson"}
      expect(response.body).to include("@hiddenprivateperson")
    end
  end

  describe "GET /search?q=... — block filter" do
    it "excludes a blocked user's matching hoojah and matching user from the blocker's results" do
      blocker = create(:user, username: "sblocker")
      blocked = create(:user, username: "sblockedtarget")
      blocker.blocks_made.create!(blocked: blocked)
      hoojah = create(:hujah, user: blocked, body: "SEARCHBLOCKED content from a blocked user")

      sign_in_fresh blocker
      get "/search", params: {q: "SEARCHBLOCKED"}
      expect(response.body).not_to include(hoojah.slug)

      get "/search", params: {q: "sblockedtarget"}
      expect(response.body).not_to include("@sblockedtarget")
    end
  end

  describe "GET /search?q=%25 — sanitize_sql_like" do
    it "matches the literal percent sign, not every row (unescaped ILIKE would match everything)" do
      literal = create(:hujah, body: "this claim literally contains a % percent sign")
      no_percent = create(:hujah, body: "totally unrelated content with no percent sign at all")

      get "/search", params: {q: "%"}
      expect(response.body).to include(literal.slug)
      expect(response.body).not_to include(no_percent.slug)
    end
  end

  # Phase 2.4 — the rich "Top matches" result UI + the browse hashtag cloud, built on
  # top of the Phase 2.2 backend the specs above already prove is visibility-safe.
  describe "GET /search?q=... — result card links" do
    it "links a hashtag result to its tag feed" do
      Hashtag.create!(name: "resulttag", display: "ResultTag")

      get "/search", params: {q: "resulttag"}

      expect(response.body).to include(%(href="/t/resulttag"))
    end

    it "links a hoojah result to the hoojah, and a person result to their profile" do
      author = create(:user, username: "cardauthor")
      hujah = create(:hujah, user: author, body: "CARDMATCH unique claim body text")

      get "/search", params: {q: "CARDMATCH"}
      expect(response.body).to include(%(href="/hoojah/#{hujah.slug}"))

      get "/search", params: {q: "cardauthor"}
      expect(response.body).to include(%(href="/u/cardauthor"))
    end

    it "renders the card-surface Follow pill (not the gradient/on-primary treatment) for a person result" do
      viewer = create(:user)
      target = create(:user, username: "followtarget")
      sign_in(viewer)

      get "/search", params: {q: "followtarget"}

      expect(response.body).to include("border-primary", "text-primary", "bg-card")
      expect(response.body).to include(follow_user_path(target.username))
    end
  end

  describe "GET /search?q=... — matched-substring highlight" do
    it "wraps the matched hashtag substring in text-primary" do
      Hashtag.create!(name: "highlighttag", display: "HighlightTag")

      get "/search", params: {q: "light"}

      expect(response.body).to include(%(<span class="text-primary">light</span>))
    end

    it "does not highlight the @handle itself, so the literal @<username> substring stays intact" do
      create(:user, username: "highlightperson")

      get "/search", params: {q: "highlightperson"}

      expect(response.body).to include("@highlightperson")
      expect(response.body).not_to include(%(@<span class="text-primary">))
    end
  end

  describe "GET /search — no results" do
    it "shows a graceful message rather than empty sections when a query matches nothing" do
      get "/search", params: {q: "nosuchmatchanywhereintheapp"}

      expect(response.body).to include("No results")
    end
  end

  describe "GET /search — browse hashtag chips" do
    it "links every browse chip to its tag feed, blank query or not" do
      Hashtag.create!(name: "browsechip", display: "BrowseChip")

      get "/search"
      expect(response.body).to include(%(href="/t/browsechip"))

      get "/search", params: {q: "somethingelseentirely"}
      expect(response.body).to include(%(href="/t/browsechip"))
    end
  end
end
