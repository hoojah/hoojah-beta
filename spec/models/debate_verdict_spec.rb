require "rails_helper"

RSpec.describe DebateVerdict, type: :model do
  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }
  let(:spectator) { create(:user) }

  def debate(status:)
    create(:debate, challenger: challenger, opponent: opponent, status: status)
  end

  describe "#cast_verdict (compute-on-read)" do
    it "records a spectator's verdict on a concluded debate" do
      d = debate(status: :concluded)
      expect(d.cast_verdict(by: spectator, choice: "challenger")).to be(true)
      expect(d.debate_verdicts.count).to eq(1)
      expect(d.verdict_tally).to eq({"challenger" => 1})
    end

    it "refuses a participant" do
      d = debate(status: :concluded)
      expect(d.cast_verdict(by: challenger, choice: "opponent")).to be(false)
      expect(d.debate_verdicts.count).to eq(0)
    end

    it "refuses when the debate is not concluded" do
      d = debate(status: :active)
      expect(d.cast_verdict(by: spectator, choice: "challenger")).to be(false)
      expect(d.debate_verdicts.count).to eq(0)
    end

    it "refuses an invalid choice" do
      d = debate(status: :concluded)
      expect(d.cast_verdict(by: spectator, choice: "nonsense")).to be(false)
      expect(d.debate_verdicts.count).to eq(0)
    end

    it "is an idempotent no-op on a second vote by the same spectator" do
      d = debate(status: :concluded)
      expect(d.cast_verdict(by: spectator, choice: "challenger")).to be(true)
      expect(d.cast_verdict(by: spectator, choice: "opponent")).to be(false)
      expect(d.debate_verdicts.count).to eq(1)
      expect(d.verdict_tally).to eq({"challenger" => 1})
    end
  end

  describe "#verdict_tally" do
    it "groups verdicts by choice" do
      d = debate(status: :concluded)
      d.cast_verdict(by: spectator, choice: "challenger")
      d.cast_verdict(by: create(:user), choice: "challenger")
      d.cast_verdict(by: create(:user), choice: "draw")
      expect(d.verdict_tally).to eq({"challenger" => 2, "draw" => 1})
    end
  end
end
