require "rails_helper"

RSpec.describe DebateVerdictPolicy do
  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }
  let(:spectator) { create(:user) }

  def debate(status:)
    create(:debate, challenger: challenger, opponent: opponent, status: status)
  end

  def verdict_for(d, user)
    d.debate_verdicts.new(user: user, choice: :challenger)
  end

  describe "#create?" do
    it "permits a visible spectator on a concluded debate" do
      d = debate(status: :concluded)
      expect(DebateVerdictPolicy.new(spectator, verdict_for(d, spectator)).create?).to be(true)
    end

    it "denies a participant" do
      d = debate(status: :concluded)
      expect(DebateVerdictPolicy.new(challenger, verdict_for(d, challenger)).create?).to be(false)
    end

    it "denies when the debate is not concluded" do
      d = debate(status: :active)
      expect(DebateVerdictPolicy.new(spectator, verdict_for(d, spectator)).create?).to be_falsey
    end

    it "denies an anonymous (nil) user" do
      d = debate(status: :concluded)
      expect(DebateVerdictPolicy.new(nil, verdict_for(d, nil)).create?).to be_falsey
    end

    it "denies a non-follower of a private participant (visibility gate)" do
      private_opponent = create(:user, private: true)
      d = create(:debate, challenger: challenger, opponent: private_opponent, status: :concluded)
      # spectator does not follow private_opponent → the debate is not visible → no verdict.
      expect(DebateVerdictPolicy.new(spectator, verdict_for(d, spectator)).create?).to be_falsey
    end
  end
end
