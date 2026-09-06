require "rails_helper"

RSpec.describe "MyDigital ID SSO", type: :request do
  it "signs in a known subject" do
    user = create(:user)
    user.identities.create!(provider: "my_digital_id", uid: "sub-known")
    mock_mydigital_id_auth(sub: "sub-known")

    post "/auth/my_digital_id"
    follow_redirect! # → callback
    expect(response).to redirect_to(root_path).or redirect_to(dashboard_path)

    # Genuinely signed in: an authenticate_user!-gated page is reachable, not bounced to login.
    get "/dashboard"
    expect(response).to have_http_status(:ok)
  end

  it "routes an unknown subject to the interstitial with a fresh pending stash" do
    mock_mydigital_id_auth(sub: "sub-new", name: "Ali bin Abu")

    post "/auth/my_digital_id"
    follow_redirect! # callback → interstitial redirect
    expect(response).to redirect_to(mydigital_id_continue_path)
    expect(session[:pending_mydid]["sub"]).to eq("sub-new")
    expect(session[:pending_mydid]["name"]).to eq("Ali bin Abu")

    follow_redirect! # → interstitial page
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("MyDigital ID")
  end

  describe "linking an existing account" do
    before { mock_mydigital_id_auth(sub: "sub-link") }

    it "links on correct credentials" do
      create(:user, email: "me@hoojah.com", password: "hoojah88", password_confirmation: "hoojah88")
      post "/auth/my_digital_id"
      follow_redirect!
      post "/mydigital-id/link", params: {email: "me@hoojah.com", password: "hoojah88"}
      expect(UserIdentity.find_by(provider: "my_digital_id", uid: "sub-link")).to be_present
      expect(response).to redirect_to(root_path).or redirect_to(dashboard_path)
    end

    it "rejects wrong credentials" do
      create(:user, email: "me@hoojah.com", password: "hoojah88", password_confirmation: "hoojah88")
      post "/auth/my_digital_id"
      follow_redirect!
      post "/mydigital-id/link", params: {email: "me@hoojah.com", password: "wrong"}
      expect(response).to have_http_status(:unprocessable_entity)
      expect(UserIdentity.find_by(provider: "my_digital_id", uid: "sub-link")).to be_nil
    end
  end

  describe "creating a new account" do
    before { mock_mydigital_id_auth(sub: "sub-create", name: "Ali bin Abu") }

    it "creates on a valid username" do
      post "/auth/my_digital_id"
      follow_redirect!
      expect {
        post "/mydigital-id/register", params: {username: "brandnew"}
      }.to change(User, :count).by(1)
      expect(User.find_by(username: "brandnew").identities.first.uid).to eq("sub-create")
    end

    it "re-renders on a taken username, creating no identity" do
      create(:user, username: "brandnew")
      post "/auth/my_digital_id"
      follow_redirect!
      expect {
        post "/mydigital-id/register", params: {username: "brandnew"}
      }.not_to change(UserIdentity, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "an already-signed-in user completes a handshake for an unknown subject" do
    # L1: a signed-in user must never be silently switched into a NEW account.
    # They get a confirmation step to link the MyDigital ID to their CURRENT account.
    it "routes to the confirmation step, not a silent create/switch" do
      user = create(:user, username: "existinguser")
      sign_in user
      mock_mydigital_id_auth(sub: "sub-si")

      post "/auth/my_digital_id"
      follow_redirect! # callback → interstitial redirect
      expect(response).to redirect_to(mydigital_id_continue_path)

      follow_redirect! # → interstitial page
      expect(response).to have_http_status(:ok)
      # Prompts to link to the CURRENT account…
      expect(response.body).to include("Link your MyDigital ID")
      expect(response.body).to include("existinguser")
      # …and does NOT offer the anonymous create-account form.
      expect(response.body).not_to include(mydigital_id_register_path)
      expect(response.body).not_to include("Create account and continue")
    end

    it "POST link-current links to the current account and creates no new user" do
      user = create(:user, username: "existinguser")
      sign_in user
      mock_mydigital_id_auth(sub: "sub-si")
      post "/auth/my_digital_id"
      follow_redirect!

      expect {
        post mydigital_id_link_current_path
      }.not_to change(User, :count)

      expect(user.reload.identities.where(provider: "my_digital_id", uid: "sub-si")).to be_present
      expect(response).to redirect_to(root_path).or redirect_to(dashboard_path)
    end

    it "refuses link-current when the current account is already linked (422, no duplicate)" do
      user = create(:user, username: "existinguser")
      user.identities.create!(provider: "my_digital_id", uid: "sub-already")
      sign_in user
      mock_mydigital_id_auth(sub: "sub-si")
      post "/auth/my_digital_id"
      follow_redirect!

      expect {
        post mydigital_id_link_current_path
      }.not_to change { user.reload.identities.count }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "redirects a signed-in POST to /register back to continue, creating no account" do
      user = create(:user, username: "existinguser")
      sign_in user
      mock_mydigital_id_auth(sub: "sub-si")
      post "/auth/my_digital_id"
      follow_redirect!

      expect {
        post "/mydigital-id/register", params: {username: "brandnew"}
      }.not_to change(User, :count)
      expect(response).to redirect_to(mydigital_id_continue_path)
    end

    it "redirects a signed-in POST to /link back to continue" do
      user = create(:user, username: "existinguser")
      sign_in user
      mock_mydigital_id_auth(sub: "sub-si")
      post "/auth/my_digital_id"
      follow_redirect!

      post "/mydigital-id/link", params: {email: "x@y.com", password: "whatever"}
      expect(response).to redirect_to(mydigital_id_continue_path)
    end
  end

  describe "a signed-in user completes a handshake for a sub linked to a DIFFERENT account" do
    # The MyDigital ID `sub-b` belongs to account B. A is signed in. We must NOT
    # silently switch A into B — A confirms the switch on the interstitial first.
    it "routes to a switch-confirmation, not a silent switch" do
      account_a = create(:user, username: "account_a")
      create(:user, username: "account_b").identities.create!(provider: "my_digital_id", uid: "sub-b")
      sign_in account_a
      mock_mydigital_id_auth(sub: "sub-b")

      post "/auth/my_digital_id"
      follow_redirect! # callback → interstitial redirect (NOT a sign-in-and-redirect)
      expect(response).to redirect_to(mydigital_id_continue_path)

      follow_redirect! # → interstitial page
      expect(response).to have_http_status(:ok)
      # Offers to SWITCH to @account_b, naming both accounts…
      expect(response.body).to include("Switch")
      expect(response.body).to include("account_b")
      # …names the CURRENT account (still signed in as A, not switched)…
      expect(response.body).to include("account_a")
      # …and does NOT render the link-current / anonymous create forms.
      expect(response.body).not_to include(mydigital_id_register_path)
      expect(response.body).not_to include(mydigital_id_link_current_path)
    end

    it "POST /mydigital-id/switch signs in as B, creating no user, clearing the stash" do
      account_a = create(:user, username: "account_a")
      create(:user, username: "account_b").identities.create!(provider: "my_digital_id", uid: "sub-b")
      sign_in account_a
      mock_mydigital_id_auth(sub: "sub-b")
      post "/auth/my_digital_id"
      follow_redirect!

      expect {
        post mydigital_id_switch_path
      }.not_to change(User, :count)
      expect(response).to redirect_to(root_path).or redirect_to(dashboard_path)
      expect(session[:pending_mydid]).to be_nil

      # Now authenticated as B, not A — the feed navbar renders the current @handle.
      get root_path
      expect(response.body).to include("account_b")
      expect(response.body).not_to include("@account_a")
    end
  end

  it "signs in a signed-in user for their OWN sub without the interstitial" do
    user = create(:user, username: "sameaccount")
    user.identities.create!(provider: "my_digital_id", uid: "sub-own")
    sign_in user
    mock_mydigital_id_auth(sub: "sub-own")

    post "/auth/my_digital_id"
    follow_redirect!
    # Same account → normal sign-in-and-redirect to the landing, never the interstitial.
    expect(response).not_to redirect_to(mydigital_id_continue_path)
    expect(response).to redirect_to(root_path).or redirect_to(dashboard_path)
    expect(session[:pending_mydid]).to be_nil
  end

  it "fails closed when the interstitial is hit with no pending stash" do
    get "/mydigital-id/continue"
    expect(response).to redirect_to(new_user_session_path)
  end

  it "renders the public MyDigital ID notice" do
    get "/mydigital-id"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("One identity, one account")
  end
end
