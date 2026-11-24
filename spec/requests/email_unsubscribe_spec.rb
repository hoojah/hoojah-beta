require "rails_helper"

RSpec.describe "Email unsubscribe", type: :request do
  let(:user) { create(:user, username: "listener", email_notifications: true) }
  let(:token) { user.generate_token_for(:email_unsubscribe) }

  describe "GET /unsubscribe/:token" do
    it "asks for confirmation without changing anything" do
      get "/unsubscribe/#{token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Stop email notifications for @listener?")
      expect(user.reload.email_notifications).to be(true)
    end

    it "says so when notifications are already off" do
      user.update!(email_notifications: false)
      get "/unsubscribe/#{token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("You won't get email notifications any more")
    end

    it "renders the invalid-link page with 404 for a bad token" do
      get "/unsubscribe/not-a-real-token"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("invalid or has expired")
    end
  end

  describe "POST /unsubscribe/:token" do
    it "turns email notifications off and redirects to the confirmation" do
      post "/unsubscribe/#{token}"

      expect(response).to redirect_to("/unsubscribe/#{token}")
      expect(user.reload.email_notifications).to be(false)
    end

    it "is idempotent" do
      2.times { post "/unsubscribe/#{token}" }

      expect(user.reload.email_notifications).to be(false)
    end

    # The mail provider's RFC 8058 POST has no CSRF token; the signed token is the
    # credential. Force forgery protection on (it is off in test) to prove the skip.
    it "accepts a one-click POST without a CSRF token and returns a bare 200" do
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      begin
        post "/unsubscribe/#{token}", params: {"List-Unsubscribe" => "One-Click"}
      ensure
        ActionController::Base.allow_forgery_protection = original
      end

      expect(response).to have_http_status(:ok)
      expect(response).not_to be_redirect
      expect(user.reload.email_notifications).to be(false)
    end

    it "returns 404 and changes nothing for an invalid token" do
      user
      post "/unsubscribe/bogus", params: {"List-Unsubscribe" => "One-Click"}

      expect(response).to have_http_status(:not_found)
      expect(user.reload.email_notifications).to be(true)
    end

    it "returns 404 for an invalid token on the HTML form too" do
      post "/unsubscribe/bogus"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("invalid or has expired")
    end
  end

  it "invalidates the link when the email address changes" do
    old_token = token
    user.update!(email: "changed_#{user.id}@hoojah.com")

    post "/unsubscribe/#{old_token}"

    expect(response).to have_http_status(:not_found)
    expect(user.reload.email_notifications).to be(true)
  end
end
