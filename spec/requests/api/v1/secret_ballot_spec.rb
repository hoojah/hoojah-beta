require "rails_helper"

# Secret ballot (2a/A7) — the API leg. HujahSerializer and UserSerializer#hujahs must
# nil the per-stance counts below k=3 total votes and always expose total_count, so a
# native client can't reconstruct the suppressed split by counting. current_user_vote
# (the viewer's own datum, not a leak) is unaffected.
RSpec.describe "Api::V1 secret ballot", type: :request do
  def body
    JSON.parse(response.body)
  end

  def attrs
    body.dig("data", "attributes")
  end

  describe "GET /api/v1/hoojah/:slug" do
    it "nils the per-stance counts and exposes total_count below k" do
      h = create(:hujah, agree_count: 1, neutral_count: 1, disagree_count: 0) # total 2

      get "/api/v1/hoojah/#{h.slug}"

      expect(response).to have_http_status(:ok)
      expect(attrs["total_count"]).to eq(2)
      expect(attrs["agree_count"]).to be_nil
      expect(attrs["neutral_count"]).to be_nil
      expect(attrs["disagree_count"]).to be_nil
      expect(attrs).to have_key("current_user_vote")
    end

    it "exposes the real per-stance counts at or above k" do
      h = create(:hujah, agree_count: 1, neutral_count: 1, disagree_count: 1) # total 3

      get "/api/v1/hoojah/#{h.slug}"

      expect(attrs["total_count"]).to eq(3)
      expect(attrs["agree_count"]).to eq(1)
      expect(attrs["neutral_count"]).to eq(1)
      expect(attrs["disagree_count"]).to eq(1)
    end

    it "still returns the viewer's own vote below k" do
      h = create(:hujah, visibility: :visible_public)
      viewer = create(:user)
      h.cast_vote(by: viewer, choice: 1) # total now 1 (sub-k)
      sign_in viewer

      get "/api/v1/hoojah/#{h.slug}"

      expect(attrs["total_count"]).to eq(1)
      expect(attrs["agree_count"]).to be_nil
      expect(attrs["current_user_vote"]).to eq("agree")
    end

    it "gates the nested children counts identically (sub-k nil, high-vote real)" do
      parent = create(:hujah, visibility: :visible_public, agree_count: 10, neutral_count: 0, disagree_count: 0)
      create(:hujah, parent: parent, user: create(:user), body: "quiet child",
        agree_count: 1, neutral_count: 1, disagree_count: 0) # total 2, sub-k
      create(:hujah, parent: parent, user: create(:user), body: "loud child",
        agree_count: 4, neutral_count: 1, disagree_count: 1) # total 6

      get "/api/v1/hoojah/#{parent.slug}"

      children = attrs["children"]
      quiet = children.find { |c| c.dig("attributes", "body") == "quiet child" }
      loud = children.find { |c| c.dig("attributes", "body") == "loud child" }
      expect(quiet.dig("attributes", "agree_count")).to be_nil
      expect(quiet.dig("attributes", "total_count")).to eq(2)
      expect(loud.dig("attributes", "agree_count")).to eq(4)
      expect(loud.dig("attributes", "total_count")).to eq(6)
    end
  end

  describe "GET /api/v1/:username — the profile hoojah list" do
    it "nils per-stance counts and adds total_count for a sub-k profile hoojah" do
      author = create(:user)
      create(:hujah, user: author, visibility: :visible_public, body: "quiet claim",
        agree_count: 1, neutral_count: 0, disagree_count: 1) # total 2, sub-k
      create(:hujah, user: author, visibility: :visible_public, body: "loud claim",
        agree_count: 4, neutral_count: 1, disagree_count: 1) # total 6

      get "/api/v1/#{author.username}"

      expect(response).to have_http_status(:ok)
      hujahs = body.dig("data", "attributes", "hujahs")
      quiet = hujahs.find { |h| h.dig("attributes", "body") == "quiet claim" }
      loud = hujahs.find { |h| h.dig("attributes", "body") == "loud claim" }
      expect(quiet.dig("attributes", "agree_count")).to be_nil
      expect(quiet.dig("attributes", "neutral_count")).to be_nil
      expect(quiet.dig("attributes", "disagree_count")).to be_nil
      expect(quiet.dig("attributes", "total_count")).to eq(2)
      expect(loud.dig("attributes", "agree_count")).to eq(4)
      expect(loud.dig("attributes", "total_count")).to eq(6)
    end
  end
end
