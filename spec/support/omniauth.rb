OmniAuth.config.test_mode = true
OmniAuth.config.logger = Rails.logger

# Devise sets OmniAuth.config.path_prefix (→ "/auth" here, from devise_for … path: "")
# while DRAWING the routes. In a request/system spec the OmniAuth strategy middleware can
# process the first POST /auth/:provider before the router has been drawn — path_prefix is
# still nil, so the strategy's request_path is "/google_oauth2", never matches "/auth/…",
# the middleware declines to intercept, and the request 404s on Devise's `passthru` action.
# Force the routes to load up front so the middleware sees the correct "/auth" prefix.
Rails.application.reload_routes!

RSpec.configure do |config|
  config.before(:each) do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end
end

module OmniauthSpecHelpers
  def mock_google_auth(email:, name: "Jane Doe", uid: "abc123")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid,
      info: {email: email, name: name}
    )
  end
end

RSpec.configure { |c| c.include OmniauthSpecHelpers }
