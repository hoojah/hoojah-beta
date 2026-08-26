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

  # verdict-k (2026): secret ballot for spectator verdicts. Below UserAnalytics::K total
  # verdicts the winner is derivable from the tiny counts (at N=1 the "winner" IS that one
  # voter's choice), so the view suppresses the winner + split. These are the model
  # predicates the view gates on. Mirrors Hujah#total_votes / #breakdown_visible?.
  describe "#total_verdicts" do
    it "sums the verdict_tally counts across every choice" do
      d = debate(status: :concluded)
      d.cast_verdict(by: spectator, choice: "challenger")
      d.cast_verdict(by: create(:user), choice: "opponent")
      d.cast_verdict(by: create(:user), choice: "draw")
      expect(d.total_verdicts).to eq(3)
    end

    it "is 0 with no verdicts" do
      expect(debate(status: :concluded).total_verdicts).to eq(0)
    end
  end

  describe "#verdict_visible?" do
    it "is false at 2 total verdicts (below k)" do
      d = debate(status: :concluded)
      d.cast_verdict(by: spectator, choice: "challenger")
      d.cast_verdict(by: create(:user), choice: "opponent")
      expect(d.verdict_visible?).to be(false)
    end

    it "is true at exactly 3 total verdicts (the k boundary)" do
      d = debate(status: :concluded)
      d.cast_verdict(by: spectator, choice: "challenger")
      d.cast_verdict(by: create(:user), choice: "challenger")
      d.cast_verdict(by: create(:user), choice: "opponent")
      expect(d.verdict_visible?).to be(true)
    end

    it "reuses the shared UserAnalytics::K threshold" do
      d = debate(status: :concluded)
      (UserAnalytics::K - 1).times { d.cast_verdict(by: create(:user), choice: "challenger") }
      expect(d.verdict_visible?).to be(false) # one short of K
      d.cast_verdict(by: create(:user), choice: "challenger")
      expect(d.total_verdicts).to eq(UserAnalytics::K)
      expect(d.verdict_visible?).to be(true) # exactly K
    end
  end

  describe "#verdict_by" do
    it "returns the user's own verdict choice as a string" do
      d = debate(status: :concluded)
      d.cast_verdict(by: spectator, choice: "opponent")
      expect(d.verdict_by(spectator)).to eq("opponent")
    end

    it "is nil for a user who has not voted" do
      d = debate(status: :concluded)
      expect(d.verdict_by(spectator)).to be_nil
    end

    it "is nil for a nil user (anonymous)" do
      d = debate(status: :concluded)
      expect(d.verdict_by(nil)).to be_nil
    end
  end
end
