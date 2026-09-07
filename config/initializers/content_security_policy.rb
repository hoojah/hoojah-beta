# Be sure to restart your server when you modify this file.
#
# Content Security Policy for the Hotwire app. Inline <script> is NOT allowed
# via 'unsafe-inline' — the two inline scripts we ship (importmap bootstrap +
# the Drift snippet) each carry a per-request nonce. Drift (appId fx42y6ieyaff)
# loads its bundle from js.driftt.com, frames js.driftt.com, and talks to
# *.drift.com over https/wss at runtime.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    # :strict_dynamic — the Drift widget, once booted, injects further <script>
    # elements at runtime that cannot carry our nonce. strict-dynamic propagates
    # trust from a nonce'd script to the scripts IT injects, which is exactly that
    # case. Under CSP3 it also makes the host allowlist below advisory (kept as a
    # fallback for pre-strict-dynamic browsers). Our own JS is safe: importmap's
    # inline bootstrap is nonce'd and its module imports inherit trust the same way.
    # (Verified by the full js:true system suite, which loads the real importmap
    # app under this enforced policy in headless Chrome.)
    policy.script_src :self, :strict_dynamic, "https://js.driftt.com", "https://*.drift.com"
    policy.style_src :self, :unsafe_inline # Tailwind ships static CSS; inline only for Turbo progress bar
    # blob: — the composer's client-side image preview: image_upload_controller
    # renders the picked file via URL.createObjectURL before/while the upload runs.
    # Attached images themselves are served SAME-ORIGIN through the Active Storage
    # proxy (ds_hujah_image_url / ds_avatar_url), so the garage host deliberately
    # does NOT appear here.
    policy.img_src :self, :data, :blob, "https://res.cloudinary.com", "https://*.drift.com"
    # The garage host: Active Storage direct uploads PUT straight from the browser
    # to a presigned URL on the S3/Garage endpoint. Same ENV expression as
    # config/storage.yml so the two can never drift.
    policy.connect_src :self, "https://*.drift.com", "wss://*.drift.com",
      ENV.fetch("GARAGE_ENDPOINT", "https://s3-grg.novas.my")
    # Drift frames its widget from js.driftt.com (the double-t asset domain), not
    # only *.drift.com — allow both so the chat iframe isn't blocked.
    policy.frame_src "https://*.drift.com", "https://*.driftt.com"
  end

  # SecureRandom, not request.session.id: the session id is blank on a
  # visitor's very first request (no cookie yet, session not persisted until
  # something writes to it), which produced an empty 'nonce-' in the CSP
  # header and an empty nonce="" on the inline Drift <script> tag — CSP
  # silently blocked Drift for every first-time anonymous visitor. A fresh
  # random nonce is generated (and memoized) per request regardless of
  # session state, so header and inline tag always agree on a real value.
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
