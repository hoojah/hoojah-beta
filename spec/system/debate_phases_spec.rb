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

  # The label lives in the turn's own pinned dom_id, so it can be asserted per row.
  # Case-insensitive because the micro-label is CSS-uppercased (`uppercase`), exactly
  # as debate_spec.rb asserts /active/i against the state label.
  def expect_phase_label(debate, position, label)
    turn = debate.turns.find_by!(position: position)
    within("##{dom_id(turn)}") { expect(page).to have_content(/#{Regexp.escape(label)}/i) }
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

  it "lets a participant extend by one round at the closing-round boundary, re-deriving the labels" do
    debate = create(:debate, hujah: root, challenger: challenger, opponent: opponent, status: :active)
    # Six turns = the closing-round boundary for rounds_limit 4: round 4 has been
    # reached but holds no turn yet, which is the only moment extend is allowed.
    6.times { |i| debate.post_turn(by: i.even? ? challenger : opponent, body: "Turn #{i + 1}.") }
    expect(debate.reload).to be_extendable_by(challenger)

    login_as_system(challenger)
    visit "/debates/#{debate.slug}"

    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/round 4 of 4/i) }
    # Turn 5 is the response round either way; turn 6 is currently the second half of it.
    expect_phase_label(debate, 5, "Response")

    click_button "Extend by one round"

    # extend_rounds.turbo_stream.erb replaces the status region in place.
    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/round 4 of 5/i) }
    expect(debate.reload.rounds_limit).to eq(5)
    # The boundary has moved, so the affordance is gone.
    within("##{dom_id(debate, :actions)}") { expect(page).to have_no_button("Extend by one round") }

    # Turn 7 now opens round 4 — no longer the closing round, so it is a counter.
    post_turn_as(challenger, debate, "Turn 7, which used to be a closing statement.")
    expect_phase_label(debate, 7, "Counter-argument")

    # And the debate no longer caps at turn 8: turn 8 is still round 4.
    post_turn_as(opponent, debate, "Turn 8, and we are not done yet.")
    expect(debate.reload).to be_active
    expect_phase_label(debate, 8, "Counter-argument")

    # Round 5 is the new closing round.
    post_turn_as(challenger, debate, "Turn 9, the real closing statement.")
    expect_phase_label(debate, 9, "Closing statement")
  end
end
