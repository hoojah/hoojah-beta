# WebAuthn Relying Party config for passkey login. `allowed_origins` is the list of
# full scheme+host values the browser may present; `rp_id` is derived from their host
# by the gem. In production this MUST include the public origin
# (https://hoojah.rudzainy.com) or every assertion fails the origin check. Dev and test
# both use http://localhost:3000 so WebAuthn::FakeClient in specs can match it without a
# Host dance. (Use allowed_origins, not the deprecated singular origin=.)
WebAuthn.configure do |config|
  config.allowed_origins = [ENV.fetch("WEBAUTHN_ORIGIN") { "http://localhost:3000" }]
  config.rp_name = "Hoojah"
  config.credential_options_timeout = 120_000 # ms the browser waits for the user gesture — restates the gem default
end
