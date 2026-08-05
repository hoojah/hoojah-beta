require "rails_helper"

RSpec.describe "Visibility", type: :model do
  let(:owner) { create(:user, private: true) }
  let(:follower) { create(:user) }
  let(:stranger) { create(:user) }
  before { follower.active_follows.create!(followed: owner, status: :accepted) }

  it "visible_to? — private: self + accepted follower only" do
    expect(owner.visible_to?(owner)).to be(true)
    expect(owner.visible_to?(follower)).to be(true)
    expect(owner.visible_to?(stranger)).to be(false)
    expect(owner.visible_to?(nil)).to be(false)
    expect(create(:user).visible_to?(stranger)).to be(true) # public
  end

  it "pending requester is NOT visible" do
    req = create(:user)
    req.active_follows.create!(followed: owner, status: :pending)
    expect(owner.visible_to?(req)).to be(false)
  end

  it "following/followers count accepted only" do
    p = create(:user)
    p.active_follows.create!(followed: owner, status: :pending)
    expect(owner.followers).to include(follower)
    expect(owner.followers).not_to include(p)
  end
end
