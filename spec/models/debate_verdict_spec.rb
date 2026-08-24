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

  # Hoojah 2026 redesign (Phase 3, Task 3.6) — the winner-hero verdict panel needs a
  # single answer from the aggregate tally, computed on read same as verdict_tally
  # (no denormalized column). Draw-safe by construction: any tie for the max —
  # including the zero-verdicts case — resolves to :draw, and so does a strict
  # majority for the :draw choice itself.
  describe "#verdict_winner" do
    it "is :draw when there are no verdicts yet" do
      d = debate(status: :concluded)
      expect(d.verdict_winner).to eq(:draw)
    end

    it "is :challenger when challenger strictly leads" do
      d = debate(status: :concluded)
      d.cast_verdict(by: spectator, choice: "challenger")
      d.cast_verdict(by: create(:user), choice: "challenger")
      d.cast_verdict(by: create(:user), choice: "opponent")
      expect(d.verdict_winner).to eq(:challenger)
    end

    it "is :opponent when opponent strictly leads" do
      d = debate(status: :concluded)
      d.cast_verdict(by: spectator, choice: "opponent")
      d.cast_verdict(by: create(:user), choice: "opponent")
      d.cast_verdict(by: create(:user), choice: "challenger")
      expect(d.verdict_winner).to eq(:opponent)
    end

    it "is :draw on an exact challenger/opponent tie" do
      d = debate(status: :concluded)
      d.cast_verdict(by: spectator, choice: "challenger")
      d.cast_verdict(by: create(:user), choice: "opponent")
      expect(d.verdict_winner).to eq(:draw)
    end

    it "is :draw when the draw choice itself has a strict majority" do
      d = debate(status: :concluded)
      d.cast_verdict(by: spectator, choice: "draw")
      d.cast_verdict(by: create(:user), choice: "draw")
      d.cast_verdict(by: create(:user), choice: "challenger")
      expect(d.verdict_winner).to eq(:draw)
    end

    it "is :draw on a three-way tie" do
      d = debate(status: :concluded)
      d.cast_verdict(by: spectator, choice: "challenger")
      d.cast_verdict(by: create(:user), choice: "opponent")
      d.cast_verdict(by: create(:user), choice: "draw")
      expect(d.verdict_winner).to eq(:draw)
    end
  end
end
