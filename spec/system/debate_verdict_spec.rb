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

  it "lets a visible spectator vote on a concluded debate and updates the tally" do
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

    # After voting: the winner-hero (Hoojah 2026, Phase 3.6), challenger crowned at
    # 100% (1/1), and the buttons are gone (a spectator's single verdict is immutable).
    expect(page).to have_css("[data-testid='verdict-hero']")
    expect(page).to have_content(/winner/i)
    expect(page).to have_content("100%")
    expect(page).to have_content("Decided by 1 spectator over #{debate.rounds_limit} rounds")
    expect(page).to have_no_button("@#{challenger.username}")
    expect(page).to have_no_button("@#{opponent.username}")
    expect(page).to have_no_button("Draw")

    expect(debate.debate_verdicts.count).to eq(1)
    expect(debate.verdict_tally).to eq({"challenger" => 1})
  end
end
