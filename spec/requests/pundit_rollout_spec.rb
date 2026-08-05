require "rails_helper"

RSpec.describe "Auth flows survive Pundit rollout", type: :request do
  it "login/signup/logout/password pages still render" do
    get "/login"
    expect(response).to have_http_status(:ok)
    get "/signup"
    expect(response).to have_http_status(:ok)
    get "/password/new"
    expect(response).to have_http_status(:ok)
  end

  it "a signed-in user can sign out" do
    sign_in create(:user)
    delete "/logout"
    expect(response).to have_http_status(:see_other).or have_http_status(:found)
  end
end
