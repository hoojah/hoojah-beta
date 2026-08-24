require "rails_helper"

RSpec.describe "Api::V1::Hujahs", type: :request do
  let(:user) { create(:user) }

  def body
    JSON.parse(response.body)
  end

  describe "GET /api/v1/hoojah/index" do
    it "returns all hoojahs in the data array" do
      create_list(:hujah, 2)

      get "/api/v1/hoojah/index"

      expect(response).to have_http_status(:ok)
      expect(body["data"]).to be_an(Array)
      # The index returns every Hujah in the database. The test DB carries a
      # small amount of pre-existing (committed) seed data, so we characterize
      # against the true total rather than the two just-created records.
      expect(body["data"].size).to eq(Hujah.count)
      expect(body["data"].size).to be >= 2
    end

    # Per-post visibility (2026): the public JSON index is a hard boundary.
    it "never includes a followers_only or private_only claim" do
      public_author = create(:user)
      create(:hujah, user: public_author, visibility: :visible_public, body: "PUBLIC api claim body")
      create(:hujah, user: public_author, visibility: :followers_only, body: "FOLLOWERSONLY api claim")
      create(:hujah, user: public_author, visibility: :private_only, body: "PRIVATEONLY api claim")

      get "/api/v1/hoojah/index"

      expect(response.body).to include("PUBLIC api claim body")
      expect(response.body).not_to include("FOLLOWERSONLY api claim")
      expect(response.body).not_to include("PRIVATEONLY api claim")
    end
  end

  describe "GET /api/v1/hoojah/:slug" do
    it "returns the matching hoojah by slug" do
      hujah = create(:hujah)

      get "/api/v1/hoojah/#{hujah.slug}"

      expect(response).to have_http_status(:ok)
      expect(body["data"]["attributes"]["slug"]).to eq(hujah.slug)
    end
  end

  describe "POST /api/v1/hoojah/create" do
    it "creates a hoojah owned by the current user" do
      login_as(user)

      expect {
        post "/api/v1/hoojah/create", params: {body: "A brand new hoojah"}
      }.to change(Hujah, :count).by(1)

      expect(Hujah.last.user).to eq(user)
    end
  end

  describe "DELETE /api/v1/hoojah/destroy/:slug" do
    let(:owner) { create(:user) }
    let(:hujah) { create(:hujah, user: owner) }

    it "rejects an unauthenticated delete" do
      delete "/api/v1/hoojah/destroy/#{hujah.slug}", as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(Hujah.exists?(hujah.id)).to be(true)
    end

    it "rejects a non-owner delete" do
      sign_in create(:user)
      delete "/api/v1/hoojah/destroy/#{hujah.slug}", as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Hujah.exists?(hujah.id)).to be(true)
    end

    it "allows the owner to delete" do
      sign_in owner
      delete "/api/v1/hoojah/destroy/#{hujah.slug}", as: :json
      expect(response).to have_http_status(:ok)
      expect(Hujah.exists?(hujah.id)).to be(false)
    end
  end
end
