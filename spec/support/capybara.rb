require "capybara/cuprite"

# Cuprite (headless Chrome via CDP) drives the `js: true` system specs. On this
# machine Chrome lives at the standard macOS app path; Ferrum auto-detects it, but
# we pass CUPRITE_CHROME_PATH explicitly when set so CI/other hosts can override.
chrome_candidates = [
  ENV["CUPRITE_CHROME_PATH"],
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium"
].compact
chrome_path = chrome_candidates.find { |p| File.executable?(p) }

# Every page renders the Drift chat widget (js.driftt.com → *.drift.com) and the
# Cloudinary upload widget (widget.cloudinary.com). Headless Chrome will happily
# hang waiting on those third-party connections, which surfaces as intermittent
# `Ferrum::PendingConnectionsError` when specs run together (the browser is shared,
# so a slow external request from one example bleeds into the next). Blocking those
# hosts at the network layer makes the suite deterministic without touching product
# code — none of the Slice 2 behaviour under test depends on the remote widgets
# (Cloudinary wiring is asserted structurally, not via a live upload).
CUPRITE_URL_BLACKLIST = [
  "*js.driftt.com*",
  "*.drift.com*",
  "*widget.cloudinary.com*",
  "*api.cloudinary.com*",
  "*res.cloudinary.com*"
].freeze

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1200, 900],
    process_timeout: 20,
    timeout: 15,
    browser_path: chrome_path,
    url_blacklist: CUPRITE_URL_BLACKLIST,
    browser_options: {"no-sandbox": nil}
  )
end

Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5
# Match buttons by aria-label (the vote buttons expose their stance that way).
Capybara.enable_aria_label = true

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :rack_test }
  config.before(:each, type: :system, js: true) { driven_by :cuprite }

  # Reset per-example browser/session state so nothing leaks between cuprite
  # examples sharing the one Chrome process (cookies, dialogs, in-flight requests).
  config.after(:each, type: :system) { Capybara.reset_sessions! }

  # Rack::Attack's user-keyed throttles (votes/compose/flags) read
  # `req.env["warden"].user` from an upstream middleware position. Under
  # Warden::Test::Helpers (login_as_system) the stashed session isn't in the shape
  # Devise 5's `serialize_from_session` expects when read that early, so it raises
  # `ArgumentError (given 10, expected 2)` and 500s the action. That's a test-harness
  # artifact, NOT a product bug: the same throttles are exercised end-to-end with real
  # logins by spec/requests/rate_limit_spec.rb (green). It also explains the observed
  # intermittency — whether it fired depended on leftover cookies in the shared Chrome.
  # System specs don't assert rate limiting, so disable Rack::Attack for them.
  config.around(:each, type: :system) do |example|
    Rack::Attack.enabled = false
    example.run
    Rack::Attack.enabled = true
  end
end
