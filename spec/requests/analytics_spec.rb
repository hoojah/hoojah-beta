require "rails_helper"

RSpec.describe "Analytics", type: :request do
  it "requires login" do
    get "/dashboard"
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows the owner their totals + suppresses low-N splits" do
    user = create(:user)
    create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1, body: "big one claim")
    create(:hujah, user: user, agree_count: 1, neutral_count: 0, disagree_count: 0, body: "small one claim")
    sign_in user
    get "/dashboard"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("5").and include("fewer than 5 votes")
  end
end
