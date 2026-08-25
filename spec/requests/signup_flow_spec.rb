# Regression: "nothing happens after I fill up sign up form and I click Sign up."
#
# Root cause was invisible_captcha's spam defense silently rejecting a legitimate
# signup, made invisible by the layout rendering no flash:
#
#   * timestamp_threshold defaulted to 4s, so any submit under 4s (autofill,
#     password managers, fast typists) tripped the check and Devise's create was
#     never reached — a bare `redirect_back` (302) with only a flash message the
#     layout never showed. See config/initializers/invisible_captcha.rb.
#   * the application layout rendered no flash at all, so this AND every other
#     Devise message ("Invalid Email or password" on login, "Signed in
#     successfully") was invisible.
#
# These specs pin both fixes: the lowered threshold lets a normally-paced signup
# through while a sub-threshold submit is still blocked, and the layout now shows
# flash messages.
require "rails_helper"

RSpec.describe "Sign-up flow (invisible_captcha regression)", type: :request do
  let(:valid_params) do
    {
      user: {
        full_name: "Real Person",
        username: "realperson",
        email: "real@example.com",
        password: "supersecret123",
        password_confirmation: "supersecret123"
      },
      subtitle: "" # the honeypot, empty for a real human
    }
  end

  it "keeps the timestamp threshold low enough for a normally-paced human" do
    # A hard floor so nobody restores the gem's 4s default and re-breaks signup.
    expect(InvisibleCaptcha.timestamp_threshold).to be <= 1
  end

  it "creates the account when the form is submitted a moment after it loads" do
    get "/signup" # stamps session[:invisible_captcha_timestamp]

    travel(2.seconds) do
      expect {
        post "/", params: valid_params
      }.to change(User, :count).by(1)

      # 303 See Other is Devise's Turbo-friendly success redirect.
      expect(response).to have_http_status(:see_other)
      expect(response.headers["Location"]).to eq(root_url)
    end
  end

  it "still blocks a sub-threshold submit (the retained spam defense)" do
    get "/signup"

    # No time travel: the POST lands milliseconds after the GET, under the
    # threshold, so invisible_captcha halts the filter chain before create.
    expect {
      post "/", params: valid_params
    }.not_to change(User, :count)
  end

  it "renders flash messages in the layout so auth feedback is visible" do
    # A bad login sets flash.now[:alert]; before the layout rendered flash, this
    # message was invisible and the login screen looked like it did nothing.
    post "/login", params: {user: {email: "nobody@example.com", password: "wrongpass"}}

    expect(response.body).to include("Invalid email or password")
    expect(response.body).to include('data-flash="alert"')
  end
end
