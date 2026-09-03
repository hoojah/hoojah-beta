# WebAuthn Relying Party config for passkey login. `origin` is the full scheme+host
# the browser sees; `rp_id` is derived from its host by the gem. In production this
# MUST be the public origin (https://hoojah.rudzainy.com) or every assertion fails
# the origin check. Dev and test both use http://localhost:3000 so WebAuthn::FakeClient
# in specs can match it without a Host dance.
WebAuthn.configure do |config|
  config.origin = ENV.fetch("WEBAUTHN_ORIGIN") { "http://localhost:3000" }
  config.rp_name = "Hoojah"
  config.credential_options_timeout = 120_000 # ms the browser waits for the user gesture
end
