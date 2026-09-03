require "rails_helper"

RSpec.describe "Passkey management", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:origin) { "http://localhost:3000" }
  let(:fake_client) { WebAuthn::FakeClient.new(origin) }
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /settings/passkeys" do
    it "renders the current user's passkeys" do
      _mine = create(:webauthn_credential, user: user, nickname: "My laptop")
      _theirs = create(:webauthn_credential, nickname: "Someone else")
      get "/settings/passkeys"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My laptop")
      expect(response.body).not_to include("Someone else")
    end

    it "renders the passkeys-empty element when the user has none" do
      # Couples index to create.turbo_stream.erb, which removes this exact id. If a
      # rename drifts the id, this fails instead of the stream silently no-op-ing.
      get "/settings/passkeys"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="passkeys-empty"')
    end
  end

  describe "POST /settings/passkeys/options" do
    it "returns creation options and lazily assigns a webauthn_id" do
      expect(user.webauthn_id).to be_nil
      post "/settings/passkeys/options"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("challenge", "user")
      expect(user.reload.webauthn_id).to be_present
    end
  end

  describe "POST /settings/passkeys" do
    it "verifies the attestation and stores the credential" do
      post "/settings/passkeys/options" # seeds session challenge + webauthn_id
      challenge = JSON.parse(response.body).fetch("challenge")
      raw = fake_client.create(challenge: challenge, user_verified: true)

      expect {
        post "/settings/passkeys",
          params: {passkey: {credential: raw, nickname: "Laptop"}}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}
      }.to change(user.webauthn_credentials, :count).by(1)

      expect(response).to redirect_to("/settings/passkeys")
      expect(user.webauthn_credentials.last.nickname).to eq("Laptop")
    end

    it "does not store a credential when verification fails" do
      post "/settings/passkeys/options"
      # A valid-but-unrelated challenge: the attestation won't match the one the
      # options endpoint stored in the session, so verification fails.
      raw = fake_client.create(challenge: WebAuthn.generate_user_id, user_verified: true)
      expect {
        post "/settings/passkeys",
          params: {passkey: {credential: raw, nickname: "Laptop"}}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}
      }.not_to change(WebauthnCredential, :count)
      expect(response).to redirect_to("/settings/passkeys")
    end

    it "does not store a credential enrolled without user verification" do
      post "/settings/passkeys/options"
      challenge = JSON.parse(response.body).fetch("challenge")
      # user_verified: false (the FakeClient default) → the UV flag is absent, so
      # create's verify(user_verification: true) rejects it: no credential persisted.
      raw = fake_client.create(challenge: challenge, user_verified: false)
      expect {
        post "/settings/passkeys",
          params: {passkey: {credential: raw, nickname: "Laptop"}}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}
      }.not_to change(WebauthnCredential, :count)
      expect(response).to redirect_to("/settings/passkeys")
    end

    it "redirects (no 500) on a structurally-malformed credential" do
      post "/settings/passkeys/options"
      # "{}" survives JSON transport but blows up inside from_create/verify. The local
      # rescue around the untrusted parse must redirect with an alert, not 500.
      expect {
        post "/settings/passkeys",
          params: {passkey: {credential: {}, nickname: "Laptop"}}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}
      }.not_to change(WebauthnCredential, :count)
      expect(response).to redirect_to("/settings/passkeys")
      expect(flash[:alert]).to be_present
    end
  end

  describe "PATCH /settings/passkeys/:id" do
    it "renames my own passkey" do
      credential = create(:webauthn_credential, user: user, nickname: "Old")
      patch "/settings/passkeys/#{credential.id}", params: {passkey: {nickname: "New"}}
      expect(credential.reload.nickname).to eq("New")
    end

    it "refuses to touch someone else's passkey" do
      # Loading via current_user.webauthn_credentials scopes to the owner, so a
      # non-owner id is simply not found → 404 (RecordNotFound), record untouched.
      others = create(:webauthn_credential, nickname: "Theirs")
      expect {
        patch "/settings/passkeys/#{others.id}", params: {passkey: {nickname: "Hacked"}}
      }.to raise_error(ActiveRecord::RecordNotFound)
      expect(others.reload.nickname).to eq("Theirs")
    end

    it "redirects with an alert and leaves the record unchanged on a duplicate nickname" do
      # A second browser tab can submit a nickname already taken by another of the
      # user's passkeys, tripping the per-user uniqueness index. Handle it gracefully
      # (RecordInvalid/RecordNotUnique) instead of 500-ing.
      create(:webauthn_credential, user: user, nickname: "Taken")
      credential = create(:webauthn_credential, user: user, nickname: "Keep")
      patch "/settings/passkeys/#{credential.id}", params: {passkey: {nickname: "Taken"}}
      expect(response).to redirect_to("/settings/passkeys")
      expect(flash[:alert]).to be_present
      expect(credential.reload.nickname).to eq("Keep")
    end
  end

  describe "DELETE /settings/passkeys/:id" do
    it "removes my own passkey" do
      credential = create(:webauthn_credential, user: user)
      expect {
        delete "/settings/passkeys/#{credential.id}"
      }.to change(user.webauthn_credentials, :count).by(-1)
    end
  end
end
