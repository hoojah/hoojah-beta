require "rails_helper"

RSpec.describe BlockPolicy do
  let(:user) { create(:user) }
  let(:other) { create(:user) }

  it "permits create for a present user, denies it for nil" do
    expect(BlockPolicy.new(user, Block.new).create?).to be(true)
    expect(BlockPolicy.new(nil, Block.new).create?).to be(false)
  end

  it "permits destroy only for the block's blocker" do
    block = Block.new(blocker: user, blocked: other)
    expect(BlockPolicy.new(user, block).destroy?).to be(true)
    expect(BlockPolicy.new(other, block).destroy?).to be(false)
    expect(BlockPolicy.new(nil, block).destroy?).to be(false)
  end
end
