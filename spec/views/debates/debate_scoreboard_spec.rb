require "rails_helper"

# Hoojah 2026 redesign (Phase 3, Task 3.4): the VS scoreboard card.
RSpec.describe "debates/_debate_scoreboard", type: :view do
  let(:challenger) { create(:user, username: "limteik") }
  let(:opponent) { create(:user, username: "sitir") }

  def html(debate)
    render(partial: "debates/debate_scoreboard", locals: {debate: debate}).strip
  end

  def scoreboard(debate)
    Capybara.string(html(debate))
  end

  context "an active debate" do
    let(:debate) { create(:debate, challenger: challenger, opponent: opponent, status: :active, rounds_limit: 4) }

    before { create(:debate_turn, debate: debate, user: challenger, position: 1) }

    it "shows both handles, VS, the derived round/phase, and the Challenger/Opponent labels" do
      s = scoreboard(debate)
      expect(s).to have_content("@limteik")
      expect(s).to have_content("@sitir")
      expect(s).to have_content("VS")
      expect(s).to have_content("Round 1 of 4")
      expect(s).to have_content("Opening statement")
      expect(s).to have_content("Challenger")
      expect(s).to have_content("Opponent")
    end

    it "shows a Live pill with a pulsing (hbreathe) dot" do
      s = scoreboard(debate)
      expect(s).to have_content("Live")
      expect(s).to have_css("[style*='hbreathe']")
    end

    # Deferred features — must not be invented here.
    it "renders no countdown timer and no spectator-lean bar" do
      html_out = html(debate)
      expect(html_out).not_to match(/\d+:\d+\s*(left|remaining)/i)
      expect(html_out).not_to include("leaning")
    end
  end

  context "a concluded debate" do
    let(:debate) { create(:debate, challenger: challenger, opponent: opponent, status: :concluded, rounds_limit: 4) }

    it "shows the trio and VS but no round/phase line and no Live pill" do
      s = scoreboard(debate)
      expect(s).to have_content("@limteik")
      expect(s).to have_content("@sitir")
      expect(s).to have_content("VS")
      expect(s).to have_no_content(/round \d+ of \d+/i)
      expect(s).to have_no_content("Live")
    end
  end
end
