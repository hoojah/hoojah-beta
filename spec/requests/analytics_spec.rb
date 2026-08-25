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

  it "shows a KPI pair for total votes received and followers, with no fabricated delta" do
    user = create(:user)
    create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1)
    other = create(:user)
    create(:follow, follower: other, followed: user, status: :accepted)
    sign_in user
    get "/dashboard"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Total votes received")
    expect(response.body).to include("Followers")
    expect(response.body).to include("1") # follower count
    expect(response.body).not_to match(/this week|% change|WoW|↑|↓/i)
  end

  it "shows a stacked distribution bar for the user's top hoojah by total votes" do
    user = create(:user)
    create(:hujah, user: user, agree_count: 1, neutral_count: 1, disagree_count: 1, body: "the smaller claim")
    create(:hujah, user: user, agree_count: 6, neutral_count: 2, disagree_count: 2, body: "the biggest claim")
    sign_in user
    get "/dashboard"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Top hoojah")
    expect(response.body).to include("the biggest claim")
    expect(response.body).to include("60%") # agree pct of the top hoojah (6/10)
  end

  it "suppresses the top-hoojah bar when even the top hoojah is under k=5" do
    user = create(:user)
    create(:hujah, user: user, agree_count: 1, neutral_count: 0, disagree_count: 0, body: "only a quiet claim")
    sign_in user
    get "/dashboard"
    expect(response.body).to include("Top hoojah")
    expect(response.body).to include("fewer than 5 votes")
  end

  it "does not build any time-series chart" do
    user = create(:user)
    create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1)
    sign_in user
    get "/dashboard"
    expect(response.body).not_to match(/last 7 days/i)
  end
end
