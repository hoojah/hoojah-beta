require "rails_helper"

# Notification + badge gating for the request/approve follow flow (Slice 7b). ALL
# follow notifications and badges live in the model, gated on ACCEPTED so a pending
# request never fires new_follower / first_follower (the v1 bug).
RSpec.describe "Follow flow (model notifications + badges)", type: :model do
  let(:follower) { create(:user) }

  describe "following a public target -> accepted" do
    let(:target) { create(:user) }

    it "fires new_follower + first_follower badge, no follow_request" do
      expect {
        follower.active_follows.create!(followed: target, status: :accepted)
      }.to change { Notification.where(user: target, category: "new_follower").count }.by(1)
      expect(target.user_badges.pluck(:badge_key)).to include("first_follower")
      expect(Notification.where(user: target, category: "follow_request").count).to eq(0)
    end
  end

  describe "following a private target -> pending request" do
    let(:target) { create(:user, private: true) }

    it "fires follow_request ONLY — no new_follower, no badge" do
      expect {
        follower.active_follows.create!(followed: target, status: :pending)
      }.to change { Notification.where(user: target, category: "follow_request").count }.by(1)
      expect(Notification.where(user: target, category: "new_follower").count).to eq(0)
      expect(target.user_badges.pluck(:badge_key)).not_to include("first_follower")
    end
  end

  describe "accepting a pending request (pending -> accepted)" do
    let(:target) { create(:user, private: true) }

    it "fires follow_accepted to the requester + new_follower + first_follower badge" do
      follow = follower.active_follows.create!(followed: target, status: :pending)
      expect {
        follow.update!(status: :accepted)
      }.to change { Notification.where(user: follower, category: "follow_accepted").count }.by(1)
        .and change { Notification.where(user: target, category: "new_follower").count }.by(1)
      expect(target.user_badges.pluck(:badge_key)).to include("first_follower")
    end
  end
end
