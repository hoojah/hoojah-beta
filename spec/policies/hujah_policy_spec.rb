require "rails_helper"

RSpec.describe HujahPolicy do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  let(:hujah) { create(:hujah, user: owner) }

  it "permits destroy only for the owner" do
    expect(HujahPolicy.new(owner, hujah).destroy?).to be(true)
    expect(HujahPolicy.new(other, hujah).destroy?).to be(false)
    expect(HujahPolicy.new(nil, hujah).destroy?).to be(false)
  end

  it "permits vote/create for any logged-in user" do
    expect(HujahPolicy.new(owner, hujah).vote?).to be(true)
    expect(HujahPolicy.new(nil, hujah).vote?).to be(false)
    expect(HujahPolicy.new(owner, hujah).create?).to be(true)
    expect(HujahPolicy.new(nil, hujah).create?).to be(false)
  end
end
