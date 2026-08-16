require "rails_helper"

# Cuprite (headless Chrome) coverage for Slice 9 Phase 3 — the DERIVED phase of a
# turn made visible:
#   * every turn in the transcript is captioned with its phase
#     (Opening statement / Counter-argument / Response / Closing statement),
#   * the status region carries a "Round n of N" counter while the debate is active,
#   * the closing turn caps the debate, which concludes and opens the verdict block,
#   * a participant standing at the closing-round boundary can extend by one round,
#     which re-derives every label under them (turn 7 stops being CLOSING).
#
# Round/phase are derived at RENDER time from `position` and `debates.rounds_limit`
# — nothing is stored on debate_turns — so the second example is the one that
# matters: it proves the derivation, not a snapshot of it.
#
# Reuses the Slice-3 `login_as_system` harness (spec/support/devise.rb re-authenticates
# the designated user on EVERY request, so switching participants mid-flow is just
# another `login_as_system`). All synchronisation is Capybara `have_*` auto-waits —
# no sleeps.
RSpec.describe "Debate phases", type: :system, js: true do
  def dom_id(*args) = ActionView::RecordIdentifier.dom_id(*args)

  let(:root) { create(:hujah, body: "Should tabs beat spaces?") }
  let(:challenger) { create(:user, username: "challengerx") }
  let(:opponent) { create(:user, username: "opponentx") }
  let!(:argument) { create(:hujah, parent: root, user: opponent, vote: 3, body: "Spaces win, obviously") }

  # One turn, posted through the browser as `user`. The transcript append is the
  # synchronisation point — Capybara waits for the body to land before returning.
  def post_turn_as(user, debate, body)
    login_as_system(user)
    visit "/debates/#{debate.slug}"
    fill_in "Your turn", with: body
    click_button "Post turn"
    within("##{dom_id(debate, :transcript)}") { expect(page).to have_content(body) }
  end

  # Scoped to `.debate-turn-phase`, NOT to the turn row: a row-wide matcher passes on
  # the turn BODY, so "Turn 9, the real closing statement." would satisfy a check for
  # "Closing statement" even if the micro-label rendered "Counter-argument" — and that
  # is the one assertion proving the closing round moved. Anchored for the same reason.
  # Case-insensitive because the label is CSS-uppercased (`uppercase`), exactly as
  # debate_spec.rb asserts /active/i against the state label.
  def expect_phase_label(debate, position, label)
    turn = debate.turns.find_by!(position: position)
    within("##{dom_id(turn)} .debate-turn-phase") do
      expect(page).to have_content(/\A#{Regexp.escape(label)}\z/i)
    end
  end

  it "labels each turn with its phase, counts rounds, and caps at the rounds limit" do
    # 1. Challenge → accept, exactly as debates/_debate_actions drives it.
    login_as_system(challenger)
    visit "/hoojah/#{root.slug}"
    click_button "Challenge to debate"
    dialog = find("dialog##{dom_id(argument, :challenge_dialog)}", visible: true)
    within(dialog) { click_button "Argue Agree" }

    within("##{dom_id(root, :debates)}") { expect(page).to have_content("@challengerx vs @opponentx") }
    debate = Debate.last
    expect(debate.rounds_limit).to eq(4) # the default — 4 rounds, 8 turns

    login_as_system(opponent)
    visit "/debates/#{debate.slug}"
    click_button "Accept"
    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/active/i) } # CSS-uppercased

    # The round counter rides the (viewer-agnostic) status region.
    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/round 1 of 4/i) }

    # 2. Eight turns, alternating. Positions 1..8 → rounds 1..4.
    8.times do |i|
      mover = i.even? ? challenger : opponent
      post_turn_as(mover, debate, "Turn number #{i + 1} of this debate.")
    end
    expect(debate.reload.turns.count).to eq(8)

    # 3. The capping turn concluded the debate (post_turn caps at final_position).
    expect(debate).to be_concluded

    # 4. Reload as a spectator: every turn carries its phase, and the verdict block
    #    (rendered only for a concluded debate) is on the page.
    spectator = create(:user, username: "spectatorx")
    login_as_system(spectator)
    visit "/debates/#{debate.slug}"

    expect_phase_label(debate, 1, "Opening statement")
    expect_phase_label(debate, 2, "Opening statement")
    expect_phase_label(debate, 3, "Counter-argument")
    expect_phase_label(debate, 5, "Response")
    expect_phase_label(debate, 7, "Closing statement")
    expect_phase_label(debate, 8, "Closing statement")

    within("##{dom_id(debate, :status)}") do
      expect(page).to have_content(/concluded/i)
      # current_phase is nil on a concluded debate, and the round counter is an
      # in-progress affordance — neither belongs on a finished transcript.
      expect(page).to have_no_content(/round \d+ of \d+/i)
    end
    expect(page).to have_css("##{dom_id(debate, :verdict)}")
    expect(page).to have_content(/spectator verdict/i) # CSS-uppercased
  end

  it "advances the counter and reveals Extend live, then re-derives the labels" do
    debate = create(:debate, hujah: root, challenger: challenger, opponent: opponent, status: :active)
    # Five turns leaves the debate mid-round-3. Turn 6 — posted below, through the
    # browser — is what closes round 3 and puts it ON the closing-round boundary.
    5.times { |i| debate.post_turn(by: i.even? ? challenger : opponent, body: "Turn #{i + 1}.") }

    login_as_system(opponent) # position 6 is even → the opponent moves
    visit "/debates/#{debate.slug}"

    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/round 3 of 4/i) }
    within("##{dom_id(debate, :actions)}") { expect(page).to have_no_button("Extend by one round") }

    fill_in "Your turn", with: "Turn 6."
    click_button "Post turn"
    within("##{dom_id(debate, :transcript)}") { expect(page).to have_content("Turn 6.") }

    # NO intervening `visit` — this is the whole point. Every transition of the round
    # counter, and the false→true flip of extendable_by?, IS a post_turn; before Slice 9
    # the turn response touched only :transcript and :composer, so the counter froze at
    # first paint and the Extend button never appeared at all (its window closes on the
    # very next turn). These two assertions fail without BOTH halves of the fix.
    expect(debate.reload).to be_extendable_by(opponent)
    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/round 4 of 4/i) }
    within("##{dom_id(debate, :actions)}") { expect(page).to have_button("Extend by one round") }

    click_button "Extend by one round"

    # extend_rounds.turbo_stream.erb replaces the status region in place.
    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/round 4 of 5/i) }
    expect(debate.reload.rounds_limit).to eq(5)
    # The boundary has moved, so the affordance is gone.
    within("##{dom_id(debate, :actions)}") { expect(page).to have_no_button("Extend by one round") }

    # Turn 5 is the response round either way — the already-painted labels did not move
    # under the reader, which is exactly what confining extend to the boundary buys.
    expect_phase_label(debate, 5, "Response")

    # Turn 7 now opens round 4 — no longer the closing round, so it is a counter.
    post_turn_as(challenger, debate, "Turn 7, which used to be a closing statement.")
    expect_phase_label(debate, 7, "Counter-argument")

    # Turn 8 at model level: that the cap moved with rounds_limit is already pinned by
    # debate_phase_spec.rb ("bumps rounds_limit by one and moves the cap with it"), and
    # re-driving it through Cuprite would buy nothing.
    debate.post_turn(by: opponent, body: "Turn 8.")
    expect(debate.reload).to be_active

    # Round 5 is the new closing round.
    post_turn_as(challenger, debate, "Turn 9, the real closing statement.")
    expect_phase_label(debate, 9, "Closing statement")
  end

  it "explains the ceiling in place of the Extend button once rounds_limit is maxed" do
    debate = create(:debate, hujah: root, challenger: challenger, opponent: opponent,
      status: :active, rounds_limit: Debate::MAX_ROUNDS)
    # (MAX_ROUNDS - 1) * 2 turns = the closing-round boundary, i.e. the exact moment
    # the Extend button WOULD be offered if the debate were not already at its ceiling.
    ((Debate::MAX_ROUNDS - 1) * 2).times do |i|
      create(:debate_turn, debate: debate, user: i.even? ? challenger : opponent)
    end
    expect(debate.reload).to be_at_round_ceiling
    expect(debate).not_to be_extendable_by(challenger)

    login_as_system(challenger)
    visit "/debates/#{debate.slug}"

    within("##{dom_id(debate, :actions)}") do
      expect(page).to have_content(/maximum rounds reached/i) # CSS-uppercased
      expect(page).to have_no_button("Extend by one round")
      expect(page).to have_button("Conclude") # the ceiling caps rounds, not the debate
    end
  end
end
