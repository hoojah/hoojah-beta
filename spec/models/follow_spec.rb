require "rails_helper"

RSpec.describe Follow, type: :model do
  let(:a) { create(:user) }
  let(:b) { create(:user) }

  it "is valid between two different users and notifies the followed" do
    expect { a.active_follows.create!(followed: b, status: :accepted) }
      .to change { Notification.where(user: b, category: "new_follower").count }.by(1)
  end

  it "rejects self-follow and duplicates" do
    expect(Follow.new(follower: a, followed: a)).not_to be_valid
    a.active_follows.create!(followed: b)
    expect(Follow.new(follower: a, followed: b)).not_to be_valid
  end

  describe "#dismiss_request_notification!" do
    let(:private_b) { create(:user, private: true) }

    it "destroys exactly the matching follow_request notification and returns the rows" do
      follow = a.active_follows.create!(followed: private_b, status: :pending)
      # The pending create fires a follow_request to the target (b).
      matching = Notification.find_by!(user_id: private_b.id, subject_user_id: a.id, category: :follow_request)
      # A different request (c → b) and a non-request notification must survive.
      c = create(:user)
      other_request = Notification.create!(user_id: private_b.id, subject_user_id: c.id, category: :follow_request)
      unrelated = Notification.create!(user_id: private_b.id, subject_user_id: a.id, category: :new_follower)

      destroyed = follow.dismiss_request_notification!

      expect(destroyed.map(&:id)).to contain_exactly(matching.id)
      expect(Notification.exists?(matching.id)).to be(false)
      expect(Notification.exists?(other_request.id)).to be(true)
      expect(Notification.exists?(unrelated.id)).to be(true)
    end
  end
end
