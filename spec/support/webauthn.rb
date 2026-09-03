# WebAuthn::FakeClient is shipped by the gem but not required by default. The
# passkey specs drive a fake authenticator through it, so pull it in for the suite.
require "webauthn/fake_client"
