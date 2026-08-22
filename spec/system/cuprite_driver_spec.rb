require "rails_helper"

# Guards the Cuprite driver wiring itself, not any product behaviour.
#
# Slice 10, found by the first CI run. `driven_by :cuprite` does NOT merely select
# a previously-registered driver: Rails' ActionDispatch::SystemTesting::Driver
# lists :cuprite as registerable alongside :selenium, so it RE-REGISTERS the name
# with its own options and silently discards everything
# `Capybara.register_driver(:cuprite)` set in spec/support/capybara.rb.
#
# Measured, with `driven_by :cuprite` and no `options:`:
#
#   process_timeout=nil timeout=nil
#   browser_options={"remote-allow-origins": "*"} url_blacklist_size=0
#
# — i.e. every setting gone, including `--no-sandbox`. That is invisible on macOS,
# where Chrome runs sandboxed without the flag and Ferrum autodetects the binary,
# and fatal on a Linux CI runner, where Chrome cannot start at all: it produces no
# websocket URL and every example dies with `Ferrum::ProcessTimeoutError ... within
# 10 seconds`. The 10 is the tell — the configured process_timeout is 20, so the
# number in the error proves the configured options were not in force.
#
# This spec fails the moment someone drops the `options:` argument, so the next
# person finds out here rather than from thirty timing-out examples on CI.
#
# NOTE on a tempting but INVALID check: setting CUPRITE_CHROME_PATH to a
# nonexistent file and expecting the launch to fail does NOT work, and briefly
# fooled this investigation. spec/support/capybara.rb selects the binary with
# `find { |p| File.executable?(p) }`, so a bogus path is filtered out and the
# macOS fallback is used — the spec passes either way and proves nothing. Assert
# on the driver's own options, as below.
RSpec.describe "Cuprite driver configuration", type: :system, js: true do
  subject(:options) { page.driver.instance_variable_get(:@options) || {} }

  it "applies the configured Ferrum timeouts" do
    expect(options[:process_timeout]).to eq(20)
    expect(options[:timeout]).to eq(15)
  end

  it "passes --no-sandbox, without which Chrome cannot start on a Linux CI runner" do
    expect(options[:browser_options]).to include(:"no-sandbox")
  end

  it "applies the third-party url_blacklist" do
    # The Drift and Cloudinary hosts. Without these the shared browser can block on
    # a third-party connection and bleed a timeout into the next example.
    expect(Array(options[:url_blacklist])).to match_array(CUPRITE_URL_BLACKLIST)
  end
end
