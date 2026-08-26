require "rails_helper"

# Cuprite (headless Chrome) coverage for the spectator verdict flow on a CONCLUDED
# debate (Slice 8). Reuses the Slice-3 `login_as_system` harness (spec/support/devise.rb
# re-authenticates the user on every request). All synchronisation is Capybara `have_*`
# auto-waits — no sleeps.
#
# Real-time two-session broadcasting is out of scope here (covered by request specs +
# Task 3.x). As a single-session proxy we ALSO assert the debate stream's
# `turbo_stream_from` subscription tag renders on the show page — Turbo emits it as a
# hidden <turbo-cable-stream-source> custom element.
RSpec.describe "Debate spectator verdict", type: :system, js: true do
  let(:challenger) { create(:user, username: "challengerx") }
  let(:opponent) { create(:user, username: "opponentx") }
  let(:spectator) { create(:user, username: "spectatorx") }
  let(:debate) do
    create(:debate, challenger: challenger, opponent: opponent, status: :concluded)
  end

  it "lets a visible spectator vote on a concluded debate but SEALS the winner below k" do
    login_as_system(spectator)
    visit debate_path(debate.slug)

    # The debate stream subscription tag renders (single-session proxy for real-time 2b).
    # It's a hidden custom element, so match with visible: :all.
    expect(page).to have_css("turbo-cable-stream-source", visible: :all)

    # An eligible, not-yet-voted spectator sees the three vote buttons.
    expect(page).to have_button("@#{challenger.username}")
    expect(page).to have_button("@#{opponent.username}")
    expect(page).to have_button("Draw")

    # Vote challenger; create.turbo_stream.erb replaces the verdict block in place.
    click_button "@#{challenger.username}"

    # verdict-k: a single verdict (N=1) is below k, so the winner + split are SEALED.
    # The hero shows the viewer's own verdict and the sealed note — never a winner or a
    # percentage that would out this lone voter. The buttons are gone (verdict is immutable).
    expect(page).to have_css("[data-testid='verdict-hero']")
    expect(page).to have_content("Your verdict: Challenger")
    expect(page).to have_content("Final verdict sealed until #{UserAnalytics::K} spectators have voted")
    expect(page).to have_content("Decided by 1 spectator over #{debate.rounds_limit} rounds")
    expect(page).to have_no_content(/winner/i)
    expect(page).to have_no_content("100%")
    expect(page).to have_no_button("@#{challenger.username}")
    expect(page).to have_no_button("@#{opponent.username}")
    expect(page).to have_no_button("Draw")

    expect(debate.debate_verdicts.count).to eq(1)
    expect(debate.verdict_tally).to eq({"challenger" => 1})
  end

  it "reveals the winner-hero once the electorate clears k (N reaches 3)" do
    # Two prior verdicts already cast by other spectators; the UI vote makes it 3 (>= k),
    # so create.turbo_stream re-renders the now-VISIBLE winner-hero in place.
    create(:debate_verdict, debate: debate, user: create(:user), choice: :challenger)
    create(:debate_verdict, debate: debate, user: create(:user), choice: :challenger)

    login_as_system(spectator)
    visit debate_path(debate.slug)

    # Still below k (N=2) before this spectator votes: no winner shown yet.
    expect(page).to have_no_content(/winner/i)

    click_button "@#{challenger.username}"

    # N=3 now — the full winner-hero appears: challenger crowned at 100% (3/3).
    expect(page).to have_css("[data-testid='verdict-hero']")
    expect(page).to have_css("svg.verdict-crown")
    expect(page).to have_content(/winner/i)
    expect(page).to have_content("100%")
    expect(page).to have_content("Decided by 3 spectators over #{debate.rounds_limit} rounds")
    expect(page).to have_no_content("sealed")

    expect(debate.verdict_tally).to eq({"challenger" => 3})
  end
end
