require "rails_helper"

RSpec.describe FollowPolicy do
  let(:user) { create(:user) }
  let(:other) { create(:user) }

  it "permits create for a present user, denies it for nil" do
    expect(FollowPolicy.new(user, Follow.new).create?).to be(true)
    expect(FollowPolicy.new(nil, Follow.new).create?).to be(false)
  end

  it "permits destroy only for the follow's follower" do
    follow = Follow.new(follower: user, followed: other)
    expect(FollowPolicy.new(user, follow).destroy?).to be(true)
    expect(FollowPolicy.new(other, follow).destroy?).to be(false)
    expect(FollowPolicy.new(nil, follow).destroy?).to be(false)
  end
end
