require "rails_helper"

RSpec.describe Follow, type: :model do
  let(:a) { create(:user) }
  let(:b) { create(:user) }

  it "is valid between two different users and notifies the followed" do
    expect { a.active_follows.create!(followed: b) }
      .to change { Notification.where(user: b, category: "new_follower").count }.by(1)
  end

  it "rejects self-follow and duplicates" do
    expect(Follow.new(follower: a, followed: a)).not_to be_valid
    a.active_follows.create!(followed: b)
    expect(Follow.new(follower: a, followed: b)).not_to be_valid
  end
end
