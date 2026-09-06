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
