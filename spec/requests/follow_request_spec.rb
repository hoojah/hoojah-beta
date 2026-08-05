require "rails_helper"

RSpec.describe "Follow requests", type: :request do
  # let! (eager): the POST targets /u/owner/follow before any test body references
  # `owner`, so the users must exist up front or set_target 404s.
  let!(:owner) { create(:user, private: true, username: "owner") }
  let!(:requester) { create(:user, username: "req") }
  let(:ts) { {"Accept" => "text/vnd.turbo-stream.html"} }

  describe "requesting to follow a private user" do
    it "creates a PENDING follow; the button shows Requested; not yet a follower" do
      sign_in requester
      post "/u/owner/follow", headers: ts
      follow = Follow.find_by(follower: requester, followed: owner)
      expect(follow).to be_pending
      expect(owner.followers).not_to include(requester)
      expect(response.body).to include("Requested")
    end

    it "notifies the target with follow_request, NOT new_follower" do
      sign_in requester
      expect { post "/u/owner/follow", headers: ts }
        .to change { Notification.where(user: owner, category: "follow_request").count }.by(1)
      expect(Notification.where(user: owner, category: "new_follower").count).to eq(0)
    end
  end

  describe "the enum-default footgun" do
    it "a follow of a PUBLIC user lands accepted" do
      pub = create(:user, username: "pub")
      sign_in requester
      post "/u/pub/follow", headers: ts
      expect(Follow.find_by(follower: requester, followed: pub)).to be_accepted
    end
  end

  describe "the followed user accepts (PATCH)" do
    it "marks it accepted and notifies both the requester and the target" do
      follow = requester.active_follows.create!(followed: owner, status: :pending)
      sign_in owner
      expect { patch follow_request_path(follow) }
        .to change { Notification.where(user: requester, category: "follow_accepted").count }.by(1)
        .and change { Notification.where(user: owner, category: "new_follower").count }.by(1)
      expect(follow.reload).to be_accepted
      expect(owner.followers).to include(requester)
    end
  end

  describe "the followed user declines (DELETE)" do
    it "removes the pending follow" do
      follow = requester.active_follows.create!(followed: owner, status: :pending)
      sign_in owner
      delete follow_request_path(follow)
      expect(Follow.exists?(follow.id)).to be(false)
    end
  end

  describe "authorization" do
    it "a third party can neither accept nor decline (403)" do
      follow = requester.active_follows.create!(followed: owner, status: :pending)
      sign_in create(:user)
      patch follow_request_path(follow), headers: ts
      expect(response).to have_http_status(:forbidden)
      delete follow_request_path(follow), headers: ts
      expect(response).to have_http_status(:forbidden)
      expect(follow.reload).to be_pending
    end

    it "requires login" do
      follow = requester.active_follows.create!(followed: owner, status: :pending)
      patch follow_request_path(follow)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
