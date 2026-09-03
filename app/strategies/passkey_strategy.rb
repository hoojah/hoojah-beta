# Warden strategy for usernameless (discoverable) passkey login. It is invoked
# explicitly by Users::SessionsController#passkey via `warden.authenticate(:passkey)`,
# NOT added to Warden's default strategies (which would run on every request).
#
# Two gotchas encoded here:
#   1. Warden's `params` are RACK-level, so a JSON body would be invisible. The
#      login form therefore posts `credential` as a form-encoded JSON string, which
#      we JSON.parse below. (Registration, an ordinary Rails controller, posts JSON.)
#   2. The challenge is read-and-deleted for single use; it is stored by
#      Users::SessionsController#passkey_options under this same session key.
class PasskeyStrategy < Warden::Strategies::Base
  CHALLENGE_KEY = "passkey_authentication_challenge"

  def valid?
    params["credential"].present?
  end

  def authenticate!
    challenge = session.delete(CHALLENGE_KEY)
    return fail!("Passkey verification failed") if challenge.blank?

    webauthn_credential = WebAuthn::Credential.from_get(JSON.parse(params["credential"]))
    stored = WebauthnCredential.find_by(external_id: webauthn_credential.id)
    return fail!("Passkey verification failed") unless stored

    webauthn_credential.verify(
      challenge,
      public_key: stored.public_key,
      sign_count: stored.sign_count
    )

    stored.update!(sign_count: webauthn_credential.sign_count, last_used_at: Time.current)
    success!(stored.user)
  rescue WebAuthn::Error, JSON::ParserError
    fail!("Passkey verification failed")
  end
end
