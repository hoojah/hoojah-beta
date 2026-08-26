require "rails_helper"

RSpec.describe "Follows", type: :request do
  let(:me) { create(:user) }
  # let! (eager): the POST targets /u/target/follow before any test body references
  # `target`, so the user must exist up front or set_target 404s (same lazy-eval
  # hazard profile_spec.rb documents).
  let!(:target) { create(:user, username: "target") }

  it "requires login" do
    post "/u/target/follow"
    expect(response).to redirect_to(new_user_session_path)
  end

  it "follows via turbo_stream and is idempotent" do
    sign_in me
    post "/u/target/follow", headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(me.following).to include(target)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    post "/u/target/follow", headers: {"Accept" => "text/vnd.turbo-stream.html"} # double
    expect(me.following.where(id: target.id).count).to eq(1) # no dup, no 500
  end

  it "unfollows" do
    sign_in me
    me.active_follows.create!(followed: target)
    delete "/u/target/follow", headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(me.reload.following).not_to include(target)
  end

  describe "DELETE /u/:username/follower (remove a follower)" do
    let(:turbo) { {"Accept" => "text/vnd.turbo-stream.html"} }
    # `fan` follows `me`; the route removes `fan` (the FOLLOWER named in :username)
    # from `me`'s (the FOLLOWED, signed-in) followers.
    let(:fan) { create(:user, username: "fan") }

    it "requires login" do
      delete "/u/fan/follower"
      expect(response).to redirect_to(new_user_session_path)
    end

    it "lets the followed user sever an accepted follower and syncs both counters" do
      fan.active_follows.create!(followed: me, status: :accepted)
      sign_in me
      expect {
        delete "/u/fan/follower", headers: turbo
      }.to change { me.reload.followers_count }.by(-1)
        .and change { fan.reload.following_count }.by(-1)
      expect(me.followers).not_to include(fan)
      # Columns stay in sync with the accepted-only scopes (the drift invariant).
      expect(me.followers_count).to eq(me.passive_follows.accepted.count)
      expect(fan.following_count).to eq(fan.active_follows.accepted.count)
    end

    it "is idempotent on a repeat delete (no 500)" do
      fan.active_follows.create!(followed: me, status: :accepted)
      sign_in me
      delete "/u/fan/follower", headers: turbo
      delete "/u/fan/follower", headers: turbo
      expect(response.status).to be_in([200, 303])
      expect(me.reload.followers_count).to eq(0)
    end

    it "does not remove a pending requester (a request is not a follower)" do
      fan.active_follows.create!(followed: me, status: :pending)
      sign_in me
      delete "/u/fan/follower", headers: turbo
      expect(me.passive_follows.pending.where(follower: fan)).to exist
    end

    it "is scoped to the signed-in user's own followers (a follower cannot sever via this route)" do
      # fan -> me (accepted). fan signs in and aims the route at `target`: it only
      # ever looks at fan's OWN passive follows, so fan's follow of me is untouched.
      fan.active_follows.create!(followed: me, status: :accepted)
      sign_in fan
      delete "/u/target/follower", headers: turbo
      expect(me.followers).to include(fan)
    end

    it "is a no-op for a third party" do
      fan.active_follows.create!(followed: me, status: :accepted)
      sign_in create(:user)
      delete "/u/fan/follower", headers: turbo
      expect(me.followers).to include(fan)
    end
  end
end
