require "rails_helper"

RSpec.describe PasskeyStrategy, type: :request do
  let(:origin) { "http://localhost:3000" }
  let(:fake_client) { WebAuthn::FakeClient.new(origin) }

  # Register a real credential in the fake authenticator AND our DB, so a later
  # assertion from the same fake_client verifies against stored bytes.
  def register_credential_for(user)
    get_options = WebAuthn::Credential.options_for_create(
      user: {id: user.webauthn_id, name: user.email, display_name: user.full_name}
    )
    raw = fake_client.create(challenge: get_options.challenge, user_verified: true)
    created = WebAuthn::Credential.from_create(raw)
    created.verify(get_options.challenge)
    user.webauthn_credentials.create!(
      external_id: created.id, public_key: created.public_key,
      sign_count: created.sign_count, nickname: "Test key"
    )
  end

  # Ask the real login-options endpoint for a challenge (also stores it in session).
  def fetch_login_challenge
    post "/login/passkey/options"
    JSON.parse(response.body).fetch("challenge")
  end

  it "signs in the owner when the assertion verifies" do
    user = create(:user, webauthn_id: WebAuthn.generate_user_id)
    register_credential_for(user)

    challenge = fetch_login_challenge
    assertion = fake_client.get(challenge: challenge, user_verified: true)
    post "/login/passkey", params: {credential: assertion.to_json}

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("redirect")
    # Warden actually signed us in: a members-only page now renders.
    get "/dashboard"
    expect(response).to have_http_status(:ok)
  end

  it "fails closed when the credential is unknown" do
    create(:user, webauthn_id: WebAuthn.generate_user_id)
    # Register a credential in the fake authenticator ONLY (never in our DB), so it
    # can produce a well-formed assertion whose external_id the strategy can't resolve.
    create_options = WebAuthn::Credential.options_for_create(
      user: {id: WebAuthn.generate_user_id, name: "ghost@example.com", display_name: "Ghost"}
    )
    fake_client.create(challenge: create_options.challenge, user_verified: true)

    challenge = fetch_login_challenge
    assertion = fake_client.get(challenge: challenge, user_verified: true)
    post "/login/passkey", params: {credential: assertion.to_json}
    expect(response).to have_http_status(:unauthorized)
  end

  it "fails closed when the challenge is missing from the session" do
    user = create(:user, webauthn_id: WebAuthn.generate_user_id)
    register_credential_for(user)
    # No call to /login/passkey/options → no challenge in session.
    assertion = fake_client.get(challenge: WebAuthn.generate_user_id, user_verified: true)
    post "/login/passkey", params: {credential: assertion.to_json}
    expect(response).to have_http_status(:unauthorized)
  end

  it "fails closed (401, not 500) on a structurally-malformed credential" do
    user = create(:user, webauthn_id: WebAuthn.generate_user_id)
    register_credential_for(user)
    fetch_login_challenge # seed a challenge so we reach the parse step
    # "{}" survives JSON.parse but blows up inside from_get/verify (NoMethodError,
    # TypeError, ArgumentError, CBOR::MalformedFormatError, …). The broad rescue must
    # turn every one of those into a 401 rather than a 500 on an unauthenticated route.
    post "/login/passkey", params: {credential: "{}"}
    expect(response).to have_http_status(:unauthorized)
  end

  it "does not run (401) when no credential param is present" do
    # valid? is false → the strategy is skipped → Warden returns nil → 401.
    post "/login/passkey"
    expect(response).to have_http_status(:unauthorized)
  end
end
