require "rails_helper"

RSpec.describe "Google OmniAuth callbacks", type: :request do
  it "signs in and redirects on success" do
    mock_google_auth(email: "oauth.new@gmail.com", uid: "u1")
    post "/auth/google_oauth2"          # request phase (POST, CSRF-protected)
    follow_redirect!                     # → /auth/google_oauth2/callback
    expect(response).to redirect_to(root_path).or redirect_to(dashboard_path)
    expect(User.find_by(uid: "u1")).to be_present
  end

  it "redirects to login on failure" do
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
    post "/auth/google_oauth2"
    follow_redirect!
    expect(response).to redirect_to(new_user_session_path)
  end
end
