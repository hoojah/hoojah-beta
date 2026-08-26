require "rails_helper"

RSpec.describe "Blocks", type: :request do
  let(:me) { create(:user) }
  let!(:target) { create(:user, username: "target") }

  it "requires login" do
    post "/u/target/block"
    expect(response).to redirect_to(new_user_session_path)
  end

  it "blocks via turbo_stream and is bidirectional" do
    sign_in me
    post "/u/target/block", headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(me.reload.hidden_user_ids).to include(target.id)
    expect(target.reload.hidden_user_ids).to include(me.id)
  end

  it "removes any reciprocal follow in BOTH directions when blocking" do
    sign_in me
    me.active_follows.create!(followed: target)   # me → target
    target.active_follows.create!(followed: me)   # target → me
    post "/u/target/block", headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(Follow.where(follower: [me, target], followed: [me, target])).to be_empty
  end

  # Counter caches (gap 8): delete_all skips Follow's callbacks, so BlocksController
  # adjusts the accepted-only columns explicitly. Drift check closes each example.
  def expect_counts_in_sync(*users)
    users.each do |user|
      user.reload
      expect(user.followers_count).to eq(user.followers.count)
      expect(user.following_count).to eq(user.following.count)
    end
  end

  it "decrements all four counts when blocking a mutual accepted pair" do
    sign_in me
    me.active_follows.create!(followed: target, status: :accepted)   # me → target
    target.active_follows.create!(followed: me, status: :accepted)   # target → me
    expect(me.reload.followers_count).to eq(1)
    expect(me.reload.following_count).to eq(1)

    post "/u/target/block", headers: {"Accept" => "text/vnd.turbo-stream.html"}

    expect(me.reload.followers_count).to eq(0)
    expect(me.reload.following_count).to eq(0)
    expect(target.reload.followers_count).to eq(0)
    expect(target.reload.following_count).to eq(0)
    expect_counts_in_sync(me, target)
  end

  it "changes no counts when blocking severs only a pending row" do
    private_target = create(:user, username: "priv", private: true)
    sign_in me
    me.active_follows.create!(followed: private_target, status: :pending)  # pending request

    post "/u/priv/block", headers: {"Accept" => "text/vnd.turbo-stream.html"}

    expect(me.reload.following_count).to eq(0)
    expect(private_target.reload.followers_count).to eq(0)
    expect_counts_in_sync(me, private_target)
  end

  it "is idempotent on a double block (no 500)" do
    sign_in me
    post "/u/target/block", headers: {"Accept" => "text/vnd.turbo-stream.html"}
    post "/u/target/block", headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(response).to have_http_status(:ok)
    expect(me.reload.blocks_made.where(blocked_id: target.id).count).to eq(1)
  end

  it "unblocks" do
    sign_in me
    me.blocks_made.create!(blocked: target)
    delete "/u/target/block", headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(me.reload.hidden_user_ids).not_to include(target.id)
  end

  it "unblocking a non-existent block does not 500" do
    sign_in me
    delete "/u/target/block", headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(response).to have_http_status(:ok)
  end

  it "renders the current user's blocked list" do
    sign_in me
    me.blocks_made.create!(blocked: target)
    get "/blocks"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("target")
  end
end
