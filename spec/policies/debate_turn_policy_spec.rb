require "rails_helper"

RSpec.describe DebateTurnPolicy do
  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }
  let(:stranger) { create(:user) }
  let(:debate) { create(:debate, challenger: challenger, opponent: opponent, status: :active) }

  # On a freshly active debate with no turns, it is the challenger's move.
  def turn_for(user) = debate.turns.new(user: user)

  it "permits create only for the debate's current_turn_user on an active debate" do
    expect(debate.current_turn_user).to eq(challenger)
    expect(DebateTurnPolicy.new(challenger, turn_for(challenger)).create?).to be(true)
  end

  it "denies the other participant when it is not their turn" do
    expect(DebateTurnPolicy.new(opponent, turn_for(opponent)).create?).to be_falsey
  end

  it "denies a non-participant and a nil user" do
    expect(DebateTurnPolicy.new(stranger, turn_for(stranger)).create?).to be_falsey
    expect(DebateTurnPolicy.new(nil, turn_for(nil)).create?).to be_falsey
  end

  it "denies create on a non-active debate" do
    pending = create(:debate, challenger: challenger, opponent: opponent, status: :pending)
    expect(DebateTurnPolicy.new(challenger, pending.turns.new(user: challenger)).create?).to be_falsey
  end
end
