# Be sure to restart your server when you modify this file.
#
# Content Security Policy for the Hotwire app. Inline <script> is NOT allowed
# via 'unsafe-inline' — the single inline script we ship (Drift) carries a
# per-request nonce instead. Drift (appId fx42y6ieyaff) loads its bundle from
# js.driftt.com and talks to *.drift.com over https/wss at runtime.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self, "https://js.driftt.com", "https://*.drift.com"
    policy.style_src :self, :unsafe_inline # Tailwind ships static CSS; inline only for Turbo progress bar
    policy.img_src :self, :data, "https://res.cloudinary.com", "https://*.drift.com"
    policy.connect_src :self, "https://*.drift.com", "wss://*.drift.com"
    policy.frame_src "https://*.drift.com"
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
