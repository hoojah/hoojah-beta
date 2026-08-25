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

# Every page renders the Drift chat widget (js.driftt.com → *.drift.com). Headless
# Chrome will happily hang waiting on those third-party connections, which surfaces
# as intermittent `Ferrum::PendingConnectionsError` when specs run together (the
# browser is shared, so a slow external request from one example bleeds into the
# next). Blocking those hosts at the network layer makes the suite deterministic
# without touching product code — no behaviour under test depends on the remote
# widget. `res.cloudinary.com` stays blocked: avatars (legacy `photo` URLs and new
# ActiveStorage-Cloudinary images) are served from there, and we don't fetch them
# live in the suite. The old client-side upload widget (widget.cloudinary.com /
# api.cloudinary.com) is gone, so those hosts no longer need blocking.
CUPRITE_URL_BLACKLIST = [
  "*js.driftt.com*",
  "*.drift.com*",
  "*res.cloudinary.com*"
].freeze

# ONE definition of the driver options, used by BOTH the standalone registration
# below and the `driven_by` call in the RSpec config.
#
# Why that matters (Slice 10, found by the first CI run):
# `driven_by :cuprite` does NOT merely select a previously-registered driver.
# Rails' ActionDispatch::SystemTesting::Driver#registerable? lists :cuprite
# alongside :selenium, so `driven_by` RE-REGISTERS the :cuprite name with its own
# options — silently discarding whatever `Capybara.register_driver(:cuprite)` set.
#
# Everything below was therefore dead for the whole life of this suite: the
# browser_path (and so CUPRITE_CHROME_PATH), --no-sandbox, process_timeout,
# timeout, window_size, AND the url_blacklist. It went unnoticed because Ferrum's
# defaults happen to work on the machine this was written on: it autodetects
# Chrome at the standard macOS path and needs no sandbox flag there.
#
# It surfaced the moment CI ran it on Linux: with no --no-sandbox, Chrome cannot
# start, produces no websocket URL, and every example dies with
# `Ferrum::ProcessTimeoutError ... within 10 seconds`. The "10" is the tell —
# process_timeout below says 20, so the number in the error proves these options
# were not the ones in force.
#
# Proof, reproducible locally: set CUPRITE_CHROME_PATH to a nonexistent file and
# run a `js: true` spec. Before this fix it passed (Ferrum ignored the bogus path
# and autodetected); after it, the launch fails as it should.
#
# A METHOD, not a frozen constant: Cuprite mutates the options hash it is handed,
# so a frozen one raises FrozenError on the first `js: true` example (verified —
# that was the first attempt at this fix). Both call sites get their own copy.
CUPRITE_CHROME_BIN = chrome_path

module CupriteDriver
  def self.options
    {
      window_size: [1200, 900],
      process_timeout: 20,
      timeout: 15,
      browser_path: CUPRITE_CHROME_BIN,
      url_blacklist: CUPRITE_URL_BLACKLIST.dup,
      browser_options: {"no-sandbox": nil}
    }
  end
end

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, **CupriteDriver.options)
end

Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5
# Match buttons by aria-label (the vote buttons expose their stance that way).
Capybara.enable_aria_label = true

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :rack_test }
  # `options:` is REQUIRED, not decorative — see the note on CupriteDriver above.
  # Without it `driven_by` re-registers :cuprite with empty options and every
  # setting above is silently discarded.
  config.before(:each, type: :system, js: true) { driven_by :cuprite, options: CupriteDriver.options }

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
