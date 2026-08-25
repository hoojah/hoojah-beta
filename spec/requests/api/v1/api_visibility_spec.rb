require "rails_helper"

RSpec.describe "Api::V1 visibility parity", type: :request do
  let(:public_author) { create(:user) }
  let(:parent) { create(:hujah, user: public_author, visibility: :visible_public) }

  describe "GET /api/v1/hoojah/:slug — nested children" do
    it "omits a private author's reply from the JSON children for an anonymous caller" do
      priv = create(:user, private: true)
      create(:hujah, user: priv, parent: parent, body: "secret reply")
      get "/api/v1/hoojah/#{parent.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("secret reply")
      expect(response.body).not_to include(priv.username)
    end

    it "omits a blocked author's reply from the JSON children for the blocker" do
      me = create(:user)
      blocked = create(:user)
      create(:hujah, user: blocked, parent: parent, body: "blocked reply")
      me.blocks_made.create!(blocked: blocked)
      sign_in me
      get "/api/v1/hoojah/#{parent.slug}"
      expect(response.body).not_to include("blocked reply")
    end

    it "still includes a public author's reply" do
      create(:hujah, user: create(:user), parent: parent, body: "open reply")
      get "/api/v1/hoojah/#{parent.slug}"
      expect(response.body).to include("open reply")
    end

    it "reports children_count as the VISIBLE count, not the raw count" do
      create(:hujah, user: create(:user), parent: parent, body: "open reply")
      create(:hujah, user: create(:user, private: true), parent: parent, body: "secret reply")
      get "/api/v1/hoojah/#{parent.slug}"
      expect(JSON.parse(response.body).dig("data", "attributes", "children_count")).to eq(1)
    end
  end

  describe "GET /api/v1/hoojah/:slug — parent block" do
    it "omits the parent block when the viewer has blocked the parent's (public) author" do
      alice = create(:user) # public
      p = create(:hujah, user: alice, visibility: :visible_public, body: "alice parent claim")
      bob = create(:user)
      r = create(:hujah, user: bob, parent: p, visibility: :visible_public, body: "bob reply body")

      me = create(:user)
      me.blocks_made.create!(blocked: alice)
      sign_in me

      get "/api/v1/hoojah/#{r.slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("bob reply body") # the reply itself is visible
      expect(response.body).not_to include("alice parent claim")
      expect(response.body).not_to include(alice.username)
    end

    it "includes the parent block for a viewer who has NOT blocked the parent author (positive control)" do
      alice = create(:user)
      p = create(:hujah, user: alice, visibility: :visible_public, body: "alice parent claim")
      bob = create(:user)
      r = create(:hujah, user: bob, parent: p, visibility: :visible_public, body: "bob reply body")

      sign_in create(:user) # unrelated viewer, no block
      get "/api/v1/hoojah/#{r.slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("alice parent claim")
    end
  end

  describe "GET /api/v1/hoojah/index — feed index" do
    it "does not serve replies (a public reply under a restricted parent must not leak)" do
      restricted_parent = create(:hujah, user: create(:user), visibility: :private_only)
      create(:hujah, user: public_author, parent: restricted_parent, body: "leaky reply")
      get "/api/v1/hoojah/index"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("leaky reply")
    end

    it "omits a blocked author's top-level hoojah for a signed-in caller" do
      me = create(:user)
      blocked = create(:user)
      create(:hujah, user: blocked, visibility: :visible_public, body: "blocked top-level")
      me.blocks_made.create!(blocked: blocked)
      sign_in me
      get "/api/v1/hoojah/index"
      expect(response.body).not_to include("blocked top-level")
    end

    it "still shows a blocked author's hoojah to an unrelated signed-out caller" do
      blocked = create(:user)
      create(:hujah, user: blocked, visibility: :visible_public, body: "still public")
      get "/api/v1/hoojah/index"
      expect(response.body).to include("still public")
    end
  end
end
