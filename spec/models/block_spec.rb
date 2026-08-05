require "rails_helper"

RSpec.describe Block, type: :model do
  let(:a) { create(:user) }
  let(:b) { create(:user) }

  it "rejects a self-block (validation)" do
    expect(Block.new(blocker: a, blocked: a)).not_to be_valid
  end

  it "is unique per (blocker, blocked) pair" do
    a.blocks_made.create!(blocked: b)
    expect(Block.new(blocker: a, blocked: b)).not_to be_valid
  end

  describe "User#hidden_user_ids (bidirectional)" do
    it "hides the blocked user from the blocker AND the blocker from the blocked" do
      a.blocks_made.create!(blocked: b)
      expect(a.hidden_user_ids).to include(b.id)
      expect(b.hidden_user_ids).to include(a.id)
    end

    it "is empty when there is no block" do
      expect(a.hidden_user_ids).to eq([])
    end

    it "de-duplicates a mutual block" do
      a.blocks_made.create!(blocked: b)
      b.blocks_made.create!(blocked: a)
      expect(a.hidden_user_ids).to eq([b.id])
    end
  end
end
