require "rails_helper"

RSpec.describe "Passkey login", type: :request do
  let(:origin) { "http://localhost:3000" }
  let(:fake_client) { WebAuthn::FakeClient.new(origin) }

  # Register a credential in BOTH the fake authenticator and the DB.
  def register!(user)
    opts = WebAuthn::Credential.options_for_create(
      user: {id: user.webauthn_id, name: user.email, display_name: user.full_name}
    )
    raw = fake_client.create(challenge: opts.challenge)
    created = WebAuthn::Credential.from_create(raw)
    created.verify(opts.challenge)
    user.webauthn_credentials.create!(
      external_id: created.id, public_key: created.public_key,
      sign_count: created.sign_count, nickname: "Key"
    )
  end

  describe "POST /login/passkey/options" do
    it "returns a discoverable-credential challenge (no allowCredentials list)" do
      post "/login/passkey/options"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["challenge"]).to be_present
      expect(body["allowCredentials"]).to be_blank
    end
  end

  describe "POST /login/passkey" do
    it "signs the owner in on a valid assertion" do
      user = create(:user, webauthn_id: WebAuthn.generate_user_id)
      register!(user)

      post "/login/passkey/options"
      challenge = JSON.parse(response.body).fetch("challenge")
      assertion = fake_client.get(challenge: challenge)

      post "/login/passkey", params: {credential: assertion.to_json}
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("redirect")

      get "/dashboard" # members-only
      expect(response).to have_http_status(:ok)
    end

    it "returns 401 on a tampered/failed assertion" do
      user = create(:user, webauthn_id: WebAuthn.generate_user_id)
      register!(user)
      post "/login/passkey/options"
      # Wrong challenge → signature won't verify.
      assertion = fake_client.get(challenge: WebAuthn.generate_user_id)
      post "/login/passkey", params: {credential: assertion.to_json}
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
