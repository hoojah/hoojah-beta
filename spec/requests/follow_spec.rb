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
end
