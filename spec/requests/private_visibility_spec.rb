require "rails_helper"

# Slice 7b — the security-critical visibility gates. One example (or more) PER gate
# in the design spec's "Visibility gates" list (1–11): every content surface that
# renders a private author's content must go through `visible_to?`. A private user
# is visible only to themselves and to an ACCEPTED follower; strangers and anonymous
# visitors must never reach the content by ANY surface (feed, trending, profile,
# hoojah show, reply thread, follower lists, debate transcript, notification body,
# reply-create, or the Api::V1 read endpoints).
RSpec.describe "Private-account visibility gates", type: :request do
  let!(:owner) { create(:user, username: "owner", private: true) }
  let!(:follower) { create(:user, username: "follower") }
  let!(:stranger) { create(:user, username: "stranger") }
  let!(:pub) { create(:user, username: "pub") }

  # In production current_user is loaded FRESH each request (see block_visibility_spec).
  def sign_in_fresh(user) = sign_in(User.find(user.id))
  before { follower.active_follows.create!(followed: owner, status: :accepted) }

  # ── Gate 1: global feed excludes a private author, UNCONDITIONALLY ────────────
  describe "Gate 1 — global feed (unconditional)" do
    let!(:owner_hoojah) { create(:hujah, user: owner, body: "OWNER private feed take") }
    let!(:pub_hoojah) { create(:hujah, user: pub, body: "PUB public feed take") }

    it "hides the private author from anonymous AND a signed-in stranger" do
      get "/"
      expect(response.body).to include("PUB public feed take")
      expect(response.body).not_to include("OWNER private feed take")

      sign_in_fresh stranger
      get "/"
      expect(response.body).to include("PUB public feed take")
      expect(response.body).not_to include("OWNER private feed take")
    end
  end

  # ── Gate 2: following feed shows a private author to an accepted follower ──────
  describe "Gate 2 — following feed (accepted-only ids)" do
    it "an accepted follower sees the private author's hoojah in their Following feed" do
      create(:hujah, user: owner, body: "OWNER following-feed take")
      sign_in_fresh follower
      get "/?filter=following"
      expect(response.body).to include("OWNER following-feed take")
    end
  end

  # ── Gate 3: trending excludes private + invalidates cache on the privacy flip ──
  describe "Gate 3 — trending" do
    before { Rails.cache.clear }

    it "excludes a private author's hoojah for anonymous and a stranger" do
      create(:hujah, user: owner, body: "OWNER trending take", agree_count: 9)
      get "/trending"
      expect(response.body).not_to include("OWNER trending take")

      sign_in_fresh stranger
      get "/trending"
      expect(response.body).not_to include("OWNER trending take")
    end

    it "invalidates the trending cache when a user flips to private (no stale leak)" do
      flipper = create(:user, username: "flipper")
      create(:hujah, user: flipper, body: "FLIPPER trending take", agree_count: 9)
      get "/trending" # warms the cache while flipper is still public
      expect(response.body).to include("FLIPPER trending take")

      flipper.update!(private: true) # after_update_commit busts "trending:v1"
      get "/trending"
      expect(response.body).not_to include("FLIPPER trending take")
    end
  end

  # ── Gate 4: gated profile (limited fields, NO hoojah list) ────────────────────
  describe "Gate 4 — profile show" do
    let!(:owner_hoojah) { create(:hujah, user: owner, body: "OWNER profile hoojah") }

    it "shows a stranger the gated header only, not the hoojah list" do
      sign_in_fresh stranger
      get "/u/owner"
      expect(response.body).to include("@owner").and include("This account is private")
      expect(response.body).not_to include("OWNER profile hoojah")
    end

    it "shows an accepted follower the full profile" do
      sign_in_fresh follower
      get "/u/owner"
      expect(response.body).to include("OWNER profile hoojah")
    end
  end

  # ── Gate 5: hoojah show denied to non-followers ───────────────────────────────
  describe "Gate 5 — hoojah show" do
    let!(:owner_hoojah) { create(:hujah, user: owner, body: "OWNER show body") }

    it "redirects a stranger and anonymous away from a private author's hoojah" do
      get "/hoojah/#{owner_hoojah.slug}"
      expect(response).to have_http_status(:redirect)

      sign_in_fresh stranger
      get "/hoojah/#{owner_hoojah.slug}"
      expect(response).to have_http_status(:redirect)
    end

    it "lets an accepted follower view it" do
      sign_in_fresh follower
      get "/hoojah/#{owner_hoojah.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("OWNER show body")
    end
  end

  # ── Gate 6: @children hides a private replier from non-followers ──────────────
  describe "Gate 6 — reply thread (@children)" do
    let!(:parent) { create(:hujah, user: pub, body: "public parent thread") }
    let!(:owner_reply) { create(:hujah, parent: parent, user: owner, body: "OWNER private reply", vote: 1) }

    it "hides the private reply from a stranger and anonymous, but shows an accepted follower" do
      get "/hoojah/#{parent.slug}"
      expect(response.body).not_to include("OWNER private reply")

      sign_in_fresh stranger
      get "/hoojah/#{parent.slug}"
      expect(response.body).not_to include("OWNER private reply")

      sign_in_fresh follower
      get "/hoojah/#{parent.slug}"
      expect(response.body).to include("OWNER private reply")
    end
  end

  # ── Gate 7: follower / following list pages gated ─────────────────────────────
  describe "Gate 7 — follower/following lists" do
    it "gates the followers list of a private user from a stranger" do
      sign_in_fresh stranger
      get "/u/owner/followers"
      expect(response).to have_http_status(:redirect)
      expect(response.body).not_to include("@follower")
    end

    it "gates the following list of a private user from a stranger" do
      owner.active_follows.create!(followed: pub, status: :accepted)
      sign_in_fresh stranger
      get "/u/owner/following"
      expect(response).to have_http_status(:redirect)
      expect(response.body).not_to include("@pub")
    end

    it "lets an accepted follower see the followers list" do
      sign_in_fresh follower
      get "/u/owner/followers"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("@follower")
    end
  end

  # ── Gate 8: concluded debate transcript gated on both participants' visibility ─
  describe "Gate 8 — debate transcript" do
    let!(:hoojah) { create(:hujah, user: pub, body: "debate host hoojah") }
    let!(:debate) do
      create(:debate, hujah: hoojah, challenger: owner, opponent: pub, status: :concluded)
    end

    it "forbids a non-follower of a private participant from the concluded transcript" do
      sign_in_fresh stranger
      get "/debates/#{debate.slug}"
      expect(response).to have_http_status(:forbidden)
    end

    it "lets an accepted follower of the private participant view the transcript" do
      sign_in_fresh follower
      get "/debates/#{debate.slug}"
      expect(response).to have_http_status(:ok)
    end
  end

  # ── Gate 9: notification body of a private hoojah not rendered ────────────────
  describe "Gate 9 — notification body (HTML card + serializer)" do
    # A private user may still mention a stranger (being addressed isn't gated),
    # but the notification must NOT render the private hoojah's body.
    let!(:mention_hoojah) { create(:hujah, user: owner, body: "@stranger SECRETMENTIONBODY") }

    it "does not render the private hoojah's body in the notifications card" do
      sign_in_fresh stranger
      get "/notifications"
      expect(response.body).to include("mentioned you")
      expect(response.body).not_to include("SECRETMENTIONBODY")
    end

    it "does not expose the private hoojah in the Api::V1 notification serializer" do
      sign_in_fresh stranger
      get "/api/v1/stranger/notifications"
      expect(response.body).not_to include("SECRETMENTIONBODY")
    end
  end

  # ── Gate 10: cannot reply to an unseen private parent ─────────────────────────
  describe "Gate 10 — HujahPolicy#create?" do
    let!(:owner_hoojah) { create(:hujah, user: owner, body: "OWNER parent") }

    it "rejects a stranger's reply to a private parent they can't see" do
      sign_in_fresh stranger
      expect {
        post "/hoojah", params: {hujah: {body: "sneaky reply", parent_id: owner_hoojah.id}}
      }.not_to change(Hujah, :count)
      expect(response).to have_http_status(:redirect)
    end

    it "allows an accepted follower to reply" do
      sign_in_fresh follower
      # 2026 vote-to-respond gate: the follower must vote on the parent before replying.
      owner_hoojah.cast_vote(by: follower, choice: 1)
      expect {
        post "/hoojah", params: {hujah: {body: "welcome reply", parent_id: owner_hoojah.id}}
      }.to change(Hujah, :count).by(1)
    end
  end

  # ── Gate 11: Api::V1 read endpoints gate a private author ─────────────────────
  describe "Gate 11 — Api::V1 read endpoints" do
    let!(:owner_hoojah) { create(:hujah, user: owner, body: "OWNER api body") }
    let!(:pub_hoojah) { create(:hujah, user: pub, body: "PUB api body") }

    it "excludes a private author from the hoojah index" do
      get "/api/v1/hoojah/index"
      expect(response.body).to include("PUB api body")
      expect(response.body).not_to include("OWNER api body")
    end

    it "denies show for a private author's hoojah but allows a public one" do
      get "/api/v1/hoojah/#{owner_hoojah.slug}"
      expect(response).not_to have_http_status(:ok)

      get "/api/v1/hoojah/#{pub_hoojah.slug}"
      expect(response).to have_http_status(:ok)
    end

    it "denies the user show for a private account but allows a public one" do
      get "/api/v1/owner"
      expect(response).not_to have_http_status(:ok)

      get "/api/v1/pub"
      expect(response).to have_http_status(:ok)
    end
  end
end
