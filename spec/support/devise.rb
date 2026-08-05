# Per-example login state for cuprite system specs. Set by `login_as_system` and
# cleared after every example. Read by the persistent Warden `on_request` hook
# below so the user is re-authenticated on EVERY request the headless browser
# makes, not just the first.
module SystemLoginState
  class << self
    attr_accessor :current_user
  end
end

# Keep the system-spec user authenticated across every request.
#
# Warden::Test's `login_as` injects the user via a ONE-SHOT `on_next_request`
# callback (warden.rb shifts it off after the first request). So in a browser
# flow the login survives only the initial `visit`; the SECOND request (click
# Follow, switch the feed tab, save a profile, load the next page) has no
# injected user and Warden falls back to reading it from the session cookie.
# Under Devise 5.0.4 + Warden 1.2.9 that deserialisation path 500s
# (`serialize_from_session` is called with the wrong arity — "given 10, expected
# 2"), which is why these specs only ever passed when an earlier example happened
# to warm the shared Chrome cookie jar. Driving the real Devise login form is not
# a workaround either: a real credential POST is rejected in this suite.
#
# Instead we register a persistent `on_request` hook (runs every request, unlike
# the one-shot injection) that re-`set_user`s the designated user with
# `store: false` — the user is present in the Warden proxy for the whole flow and
# the broken session serialiser is never invoked. The hook is a no-op whenever no
# system login is active (`current_user` nil), so request specs (which use
# `sign_in`) are unaffected.
Warden::Manager.on_request do |proxy|
  user = SystemLoginState.current_user
  next if user.nil? || proxy.asset_request?

  proxy.set_user(user, scope: :user, store: false, run_callbacks: false)
end

module SystemAuthHelpers
  # Log a user into cuprite system specs for the duration of the example. Backed
  # by the persistent Warden hook above (see the long note there for why the
  # stock one-shot injection / real-form login do not work here).
  def login_as_system(user)
    SystemLoginState.current_user = user
  end
end

RSpec.configure do |config|
  config.include Warden::Test::Helpers
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include SystemAuthHelpers, type: :system
  config.after(:each) do
    SystemLoginState.current_user = nil
    Warden.test_reset!
  end
end
