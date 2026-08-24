require "rails_helper"

RSpec.describe "Profile", type: :request do
  # let! (eager): the non-owner test patches /u/rudz before it otherwise touches
  # `user`, so rudz must exist up front or set_user 404s before authorization runs.
  let!(:user) { create(:user, username: "rudz") }

  it "shows a public profile with the user hoojahs" do
    create(:hujah, user: user, body: "hello world")
    get "/u/rudz"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("@rudz").and include("hello world")
  end

  # ── Per-post visibility (2026): profile hoojah list is scoped per viewer ─────────
  it "hides a public user's followers_only and private_only claims from a stranger" do
    create(:hujah, user: user, visibility: :visible_public, body: "PUBLIC profile claim body")
    create(:hujah, user: user, visibility: :followers_only, body: "FOLLOWERS profile secret")
    create(:hujah, user: user, visibility: :private_only, body: "PRIVATE profile secret")
    get "/u/rudz"
    expect(response.body).to include("PUBLIC profile claim body")
    expect(response.body).not_to include("FOLLOWERS profile secret")
    expect(response.body).not_to include("PRIVATE profile secret")
  end

  it "shows followers_only claims to an accepted follower, private_only only to self" do
    create(:hujah, user: user, visibility: :followers_only, body: "FOLLOWERS profile secret")
    create(:hujah, user: user, visibility: :private_only, body: "PRIVATE profile secret")
    fan = create(:user, username: "profilefan")
    fan.active_follows.create!(followed: user, status: :accepted)
    sign_in fan
    get "/u/rudz"
    expect(response.body).to include("FOLLOWERS profile secret")
    expect(response.body).not_to include("PRIVATE profile secret")

    sign_in user
    get "/u/rudz"
    expect(response.body).to include("PRIVATE profile secret")
  end

  it "lets the owner update and rejects a bad link (M7) / bad photo host" do
    sign_in user
    patch "/u/rudz", params: {user: {headline: "hi", link: "javascript:alert(1)"}},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(user.reload.headline).not_to eq("hi") # validation blocked the whole update
    patch "/u/rudz", params: {user: {photo: "https://res.cloudinary.com.evil.com/hoojah/x.jpg"}}
    expect(user.reload.photo).not_to include("evil.com")
  end

  it "shows the followers list publicly (signed out)" do
    fan = create(:user, username: "fan")
    fan.active_follows.create!(followed: user, status: :accepted)
    get "/u/rudz/followers"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("@fan")
  end

  it "shows the following list publicly (signed out)" do
    idol = create(:user, username: "idol")
    user.active_follows.create!(followed: idol, status: :accepted)
    get "/u/rudz/following"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("@idol")
  end

  it "lets the owner toggle their account private" do
    sign_in user
    patch "/u/rudz", params: {user: {private: "1"}},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(user.reload).to be_private
  end

  it "auto-accepts pending follow requests when flipping private -> public" do
    user.update!(private: true)
    requester = create(:user, username: "req")
    pending = requester.active_follows.create!(followed: user, status: :pending)
    sign_in user
    patch "/u/rudz", params: {user: {private: "0"}},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(user.reload).not_to be_private
    expect(pending.reload).to be_accepted
  end

  it "forbids editing someone else" do
    sign_in create(:user)
    patch "/u/rudz", params: {user: {headline: "hacked"}},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(response).to have_http_status(:forbidden)
    expect(user.reload.headline).not_to eq("hacked")
  end
end
