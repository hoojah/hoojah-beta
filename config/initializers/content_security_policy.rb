# Be sure to restart your server when you modify this file.
#
# Content Security Policy for the Hotwire app. Inline <script> is NOT allowed
# via 'unsafe-inline' — the two inline scripts we ship (the no-FOUC theme script
# and importmap's bootstrap) each carry a per-request nonce. Everything else is
# same-origin: importmap loads the app bundle and its modules from 'self', so a
# plain nonce-plus-self script policy covers the whole app with no third-party
# hosts. (The Drift live-chat widget was removed — its bootstrap API 400'd and it
# was the only reason this policy ever needed strict-dynamic + external hosts.)
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    # 'self' + the per-request nonce (see nonce_directives below): the nonce admits
    # our two inline <script>s, and 'self' admits importmap's module bundle and
    # every app module it imports. No 'unsafe-inline', no host allowlist, no
    # strict-dynamic — nothing runtime-injects scripts anymore.
    policy.script_src :self
    policy.style_src :self, :unsafe_inline # Tailwind ships static CSS; inline only for Turbo progress bar
    # blob: — the composer's client-side image preview: image_upload_controller
    # renders the picked file via URL.createObjectURL before/while the upload runs.
    # Attached images are served SAME-ORIGIN through the Active Storage proxy
    # (ds_hujah_image_url / ds_avatar_url), so the garage host is not needed here;
    # res.cloudinary.com stays for legacy direct-Cloudinary avatar URLs.
    policy.img_src :self, :data, :blob, "https://res.cloudinary.com"
    # The garage host: Active Storage direct uploads PUT straight from the browser
    # to a presigned URL on the S3/Garage endpoint. Same ENV expression as
    # config/storage.yml so the two can never drift.
    policy.connect_src :self, ENV.fetch("GARAGE_ENDPOINT", "https://s3-grg.novas.my")
    # No frame-src: nothing embeds a third-party iframe anymore, so it inherits
    # default-src 'self'.
  end

  # SecureRandom, not request.session.id: the session id is blank on a
  # visitor's very first request (no cookie yet, session not persisted until
  # something writes to it), which produced an empty 'nonce-' in the CSP header
  # and an empty nonce="" on our inline <script> tags — CSP would then silently
  # block them (e.g. a light-mode flash from the blocked no-FOUC script) for
  # every first-time anonymous visitor. A fresh random nonce is generated (and
  # memoized) per request regardless of session state, so header and inline tags
  # always agree on a real value.
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
