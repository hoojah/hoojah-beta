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
end
