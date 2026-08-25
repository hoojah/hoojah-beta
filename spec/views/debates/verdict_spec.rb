require "rails_helper"

# Hoojah 2026 redesign (Phase 3, Task 3.6): the CONCLUDED-debate verdict panel,
# restyled as the winner-hero mockup (~lines 1216-1275). Preserves the spectator
# voting flow, the secret-ballot invariant (aggregate `verdict_tally` only — no
# per-voter identity ever reaches the view), and the pinned `dom_id(debate, :verdict)`.
RSpec.describe "debates/_verdict", type: :view do
  let(:challenger) { create(:user, username: "limteik") }
  let(:opponent) { create(:user, username: "sitir") }
  let(:spectator) { create(:user, username: "spectatorx") }

  def debate(status: :concluded, rounds_limit: 3)
    create(:debate, challenger: challenger, opponent: opponent, status: status, rounds_limit: rounds_limit)
  end

  def dom_id(*args) = ActionView::RecordIdentifier.dom_id(*args)

  def as(user)
    allow(view).to receive(:user_signed_in?).and_return(user.present?)
    allow(view).to receive(:current_user).and_return(user)
  end

  def html(d)
    render(partial: "debates/verdict", locals: {debate: d}).strip
  end

  def panel(d)
    Capybara.string(html(d))
  end

  it "still shows the pinned dom_id(:verdict) wrapper" do
    d = debate
    as(spectator)
    expect(panel(d)).to have_css("##{dom_id(d, :verdict)}")
  end

  it "still shows the three vote buttons for an eligible, not-yet-voted spectator (voting flow preserved)" do
    d = debate
    as(spectator)
    p = panel(d)
    expect(p).to have_button("@#{challenger.username}")
    expect(p).to have_button("@#{opponent.username}")
    expect(p).to have_button("Draw")
    # The hero must not render yet — nobody has voted.
    expect(p).to have_no_content(/winner/i)
  end

  it "does not show vote buttons to a participant" do
    d = debate
    as(challenger)
    p = panel(d)
    expect(p).to have_no_button("@#{opponent.username}")
  end

  context "winner hero (a spectator has voted, or a participant is viewing)" do
    # Participants are never eligible to vote (DebateVerdictPolicy#create? excludes
    # them), so `as(challenger)` reliably lands on the hero branch regardless of the
    # tally below — unlike an un-voted spectator, who would still see the vote
    # buttons no matter how the OTHER spectators voted. That path is covered
    # separately, below.
    it "crowns the challenger as winner when they have strictly more verdicts" do
      d = debate(rounds_limit: 3)
      create(:debate_verdict, debate: d, choice: :challenger)
      create(:debate_verdict, debate: d, choice: :challenger)
      create(:debate_verdict, debate: d, choice: :opponent)
      as(challenger)
      p = panel(d)

      expect(p).to have_no_button("@#{opponent.username}")
      expect(p).to have_content(/winner/i)
      expect(p).to have_content("@#{challenger.username}")
      expect(p).to have_css("[data-testid='verdict-hero']")
      expect(p).to have_css("svg.verdict-crown")
      # The single result bar's percentages: 2/3 challenger, 1/3 opponent.
      expect(p).to have_content("67%")
      expect(p).to have_content("33%")
      # Footnote: N spectators (verdict count), M rounds (rounds_limit).
      expect(p).to have_content("Decided by 3 spectators over 3 rounds")
    end

    it "crowns the opponent as winner when they have strictly more verdicts" do
      d = debate
      create(:debate_verdict, debate: d, choice: :opponent)
      create(:debate_verdict, debate: d, choice: :opponent)
      create(:debate_verdict, debate: d, choice: :challenger)
      as(opponent)
      p = panel(d)

      expect(p).to have_content(/winner/i)
      expect(p).to have_css("svg.verdict-crown")
    end

    it "shows the hero (not the vote buttons) once the viewing spectator has voted" do
      d = debate
      create(:debate_verdict, debate: d, user: spectator, choice: :challenger)
      as(spectator)
      p = panel(d)

      expect(p).to have_no_button("@#{challenger.username}")
      expect(p).to have_css("[data-testid='verdict-hero']")
    end

    it "renders a Draw hero with NO crown on an exact challenger/opponent tie" do
      d = debate
      create(:debate_verdict, debate: d, choice: :challenger)
      create(:debate_verdict, debate: d, choice: :opponent)
      as(challenger)
      p = panel(d)

      expect(p).to have_css("[data-testid='verdict-hero']", text: /draw/i)
      expect(p).to have_no_content(/winner/i)
      expect(p).to have_no_css("svg.verdict-crown")
    end

    it "renders a Draw hero with NO crown when the draw choice itself has a majority" do
      d = debate
      create(:debate_verdict, debate: d, choice: :draw)
      create(:debate_verdict, debate: d, choice: :draw)
      create(:debate_verdict, debate: d, choice: :challenger)
      as(challenger)
      p = panel(d)

      expect(p).to have_css("[data-testid='verdict-hero']", text: /draw/i)
      expect(p).to have_no_content(/winner/i)
      expect(p).to have_no_css("svg.verdict-crown")
    end

    it "renders a Draw hero with NO crown when there are no verdicts yet" do
      d = debate
      as(challenger) # a participant views their own concluded debate
      p = panel(d)

      expect(p).to have_css("[data-testid='verdict-hero']", text: /draw/i)
      expect(p).to have_no_css("svg.verdict-crown")
      expect(p).to have_content("Decided by 0 spectators over 3 rounds")
    end

    it "shows only the aggregate tally — no per-voter identity (secret ballot)" do
      voter_a = create(:user, username: "voteralpha")
      voter_b = create(:user, username: "voterbeta")
      d = debate
      create(:debate_verdict, debate: d, user: voter_a, choice: :challenger)
      create(:debate_verdict, debate: d, user: voter_b, choice: :opponent)
      as(spectator)
      out = html(d)

      expect(out).not_to include("voteralpha")
      expect(out).not_to include("voterbeta")
    end

    it "shows each participant's closing-phase turn, labelled with the speaker's stance colour" do
      d = debate(rounds_limit: 2) # closing round = round 2 = positions 3, 4
      create(:debate_turn, debate: d, user: challenger, position: 1, body: "Opening line.")
      create(:debate_turn, debate: d, user: opponent, position: 2, body: "Opening reply.")
      create(:debate_turn, debate: d, user: challenger, position: 3, body: "Challenger closing remark.")
      create(:debate_turn, debate: d, user: opponent, position: 4, body: "Opponent closing remark.")
      as(challenger)
      p = panel(d)

      expect(p).to have_content("Challenger closing remark.")
      expect(p).to have_content("Opponent closing remark.")
      expect(p).to have_no_content("Opening line.")
      expect(p).to have_css(".text-agree", text: "@#{challenger.username}")
      expect(p).to have_css(".text-disagree", text: "@#{opponent.username}")
    end

    it "offers a Share affordance linking to the debate" do
      d = debate
      as(challenger)
      out = html(d)

      expect(out).to include('data-controller="share"')
      expect(out).to include(debate_url(d.slug))
    end
  end
end
