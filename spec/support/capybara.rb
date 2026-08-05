require "capybara/cuprite"

# Cuprite (headless Chrome via CDP) drives the `js: true` system specs. On this
# machine Chrome lives at the standard macOS app path; Ferrum auto-detects it, but
# we pass CUPRITE_CHROME_PATH explicitly when set so CI/other hosts can override.
_chrome_candidates = [
  ENV["CUPRITE_CHROME_PATH"],
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium"
].compact
_chrome_path = _chrome_candidates.find { |p| File.executable?(p) }

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1200, 900],
    process_timeout: 20,
    browser_path: _chrome_path,
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
end
