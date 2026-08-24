require "rails_helper"

# Cuprite (headless Chrome) coverage for the full debate flow, request-driven Turbo
# Streams throughout (broadcasting is Increment 2b):
#   challenge (open the argument's dialog → pick an opposing stance → POST) →
#   opponent accepts → alternating turns append in place + the composer refocuses →
#   either party concludes → the transcript is read-only.
#
# Reuses the Slice-3 `login_as_system` harness (spec/support/devise.rb re-authenticates
# the designated user on EVERY request, so switching participants mid-flow is just
# another `login_as_system`). All synchronisation is Capybara `have_*` auto-waits —
# no sleeps.
RSpec.describe "Debate", type: :system, js: true do
  def dom_id(*args) = ActionView::RecordIdentifier.dom_id(*args)

  let(:root) { create(:hujah, body: "Should tabs beat spaces?") }
  let(:challenger) { create(:user, username: "challengerx") }
  let(:opponent) { create(:user, username: "opponentx") }
  # The opponent's argument (Disagree) on the root hoojah — the debate is anchored to it.
  let!(:argument) { create(:hujah, parent: root, user: opponent, vote: 3, body: "Spaces win, obviously") }

  it "drives challenge → accept → alternating turns → conclude → read-only transcript" do
    # 1. Challenger follows the "Challenge to debate" link to the create page (Phase
    # 3.2 — no more stance-only dialog), picks the opposing stance, and leaves the
    # opening argument blank so `accept!` behaves exactly as before this page existed
    # (no auto-posted opening turn) — the rest of this flow is otherwise unchanged.
    login_as_system(challenger)
    visit "/hoojah/#{root.slug}"

    expect(page).to have_content("Spaces win, obviously")
    click_link "Challenge to debate"

    expect(page).to have_current_path(%r{/hoojah/#{root.slug}/debates/new})
    choose("challenger_stance", option: "1", allow_label_click: true) # opposes the argument's stance (3, Disagree)
    click_button "Send challenge"

    debate = Debate.last
    expect(page).to have_current_path("/debates/#{debate.slug}")
    expect(debate).to be_pending
    expect(debate.opening_argument).to be_blank

    # 2. Opponent accepts the challenge (from the debate transcript screen). Phase 3.3
    # (2026 redesign): a pending debate gets a dedicated accept/decline screen — assert
    # its content (avatar trio, headline, motion, rules card, no timer row) BEFORE
    # accepting, still via the pinned `_debate_actions` buttons.
    login_as_system(opponent)
    visit "/debates/#{debate.slug}"

    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/pending/i) } # CSS-uppercased
    expect(page).to have_css("[aria-label='#{challenger.full_name}']")
    expect(page).to have_css("[aria-label='#{opponent.full_name}']")
    expect(page).to have_content("@#{challenger.username}")
    expect(page).to have_content("Should tabs beat spaces?")
    expect(page).to have_content("#{debate.rounds_limit} rounds")
    expect(page).to have_content("Spectators")
    expect(page).to have_no_content("per turn")
    within("##{dom_id(debate, :actions)}") { expect(page).to have_button("Accept") and have_button("Decline") }

    click_button "Accept"

    # Status flips to Active in place; the opponent now waits for the challenger.
    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/active/i) } # CSS-uppercased
    within("##{dom_id(debate, :composer)}") { expect(page).to have_content("Waiting for @challengerx") }
    expect(debate.reload).to be_active

    # 3. Challenger's turn: the composer renders focused (connect() refocus) on first paint.
    # A fresh `visit` also picks up the else-branch's structural HTML for the first
    # time — accept! only Turbo-Stream-replaces :status/:actions in place, so the
    # scoreboard (rendered around, not inside, the pending screen it replaces) only
    # appears after a real page load.
    login_as_system(challenger)
    visit "/debates/#{debate.slug}"
    expect(page).to have_css("textarea[aria-label='Your turn']:focus")

    # 3a. Phase 3.4 — the VS scoreboard: both handles, the derived round/phase, and a
    # Live pill with a pulsing (hbreathe) dot. No countdown, no spectator-lean bar.
    # Round/VS/phase/Live are CSS-uppercased (`uppercase`), hence the case-insensitive
    # matches — same convention `debate_phases_spec.rb` already uses for :status.
    within(".debate-scoreboard") do
      expect(page).to have_content("@challengerx")
      expect(page).to have_content("@opponentx")
      expect(page).to have_content(/round 1 of #{debate.rounds_limit}/i)
      expect(page).to have_content(/opening statement/i)
      expect(page).to have_content(/live/i)
    end
    expect(page).to have_no_content(/leaning/i)

    fill_in "Your turn", with: "Tabs are one keystroke."
    click_button "Post turn"

    # The turn appends into the pinned transcript IN PLACE; the composer replaces to
    # the waiting state for the mover (no full navigation).
    within("##{dom_id(debate, :transcript)}") { expect(page).to have_content("Tabs are one keystroke.") }
    within("##{dom_id(debate, :composer)}") { expect(page).to have_content("Waiting for @opponentx") }

    # 3b. Phase 3.4 — the challenger's turn renders as a chat bubble aligned to the
    # start, agree-coloured, carrying the "Phase · @handle" micro-label (also
    # CSS-uppercased).
    challenger_turn = debate.turns.find_by!(user: challenger)
    # The alignment class lives on the dom_id ROOT itself, not a descendant — combine
    # both into one selector rather than `within`, which only searches descendants.
    expect(page).to have_css("##{dom_id(challenger_turn)}.self-start")
    within("##{dom_id(challenger_turn)}") { expect(page).to have_content(/opening statement · @challengerx/i) }

    # 4. Opponent's turn: composer refocuses again on render, then they post.
    login_as_system(opponent)
    visit "/debates/#{debate.slug}"
    expect(page).to have_css("textarea[aria-label='Your turn']:focus")

    fill_in "Your turn", with: "Spaces are unambiguous."
    click_button "Post turn"

    within "##{dom_id(debate, :transcript)}" do
      expect(page).to have_content("Tabs are one keystroke.")
      expect(page).to have_content("Spaces are unambiguous.")
    end

    # 4b. The opponent's turn bubble aligns to the end, disagree-coloured.
    opponent_turn = debate.turns.find_by!(user: opponent)
    expect(page).to have_css("##{dom_id(opponent_turn)}.self-end")
    within("##{dom_id(opponent_turn)}") { expect(page).to have_content(/opening statement · @opponentx/i) }

    # 5. Either participant concludes (opponent is the current viewer).
    click_button "Conclude"
    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/concluded/i) } # CSS-uppercased
    expect(debate.reload).to be_concluded

    # 6. The transcript is read-only afterwards — no composer form, turns still shown,
    #    and it is publicly visible (logged-out) since it concluded.
    login_as_system(nil)
    Capybara.reset_sessions!
    visit "/debates/#{debate.slug}"
    expect(page).to have_content("Tabs are one keystroke.")
    expect(page).to have_content("Spaces are unambiguous.")
    expect(page).to have_no_css("textarea")
    expect(page).to have_no_button("Post turn")
  end

  # Phase 3.3: the pending accept/decline screen's Decline path — still the existing
  # `_debate_actions` `button_to`, just reached through the new layout.
  it "opponent can decline from the pending accept/decline screen" do
    login_as_system(challenger)
    visit "/hoojah/#{root.slug}"
    click_link "Challenge to debate"
    expect(page).to have_current_path(%r{/hoojah/#{root.slug}/debates/new})
    choose("challenger_stance", option: "1", allow_label_click: true)
    click_button "Send challenge"
    debate = Debate.last

    login_as_system(opponent)
    visit "/debates/#{debate.slug}"
    within("##{dom_id(debate, :actions)}") { click_button "Decline" }

    within("##{dom_id(debate, :status)}") { expect(page).to have_content(/declined/i) } # CSS-uppercased
    expect(page).to have_no_button("Accept")
    expect(page).to have_no_button("Decline")
    expect(debate.reload).to be_declined
  end
end
