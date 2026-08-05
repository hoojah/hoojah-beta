require "rails_helper"

RSpec.describe FollowRequestPolicy do
  let(:owner) { create(:user) }
  let(:requester) { create(:user) }
  let(:follow) { Follow.new(follower: requester, followed: owner) }

  it "permits the followed user (the request's target) to accept/decline" do
    expect(FollowRequestPolicy.new(owner, follow).update?).to be(true)
    expect(FollowRequestPolicy.new(owner, follow).destroy?).to be(true)
  end

  it "denies the requester and any third party" do
    expect(FollowRequestPolicy.new(requester, follow).update?).to be(false)
    expect(FollowRequestPolicy.new(create(:user), follow).destroy?).to be(false)
  end

  it "denies an anonymous (nil) user" do
    expect(FollowRequestPolicy.new(nil, follow).update?).to be(false)
    expect(FollowRequestPolicy.new(nil, follow).destroy?).to be(false)
  end
end
