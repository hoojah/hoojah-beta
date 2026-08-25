require "rails_helper"

# Cuprite coverage for the 2026 debate CREATE PAGE (Phase 3.2), which replaces the
# stance-only <dialog> as the primary "Challenge to debate" entry point. The dialog
# partial itself still exists but is no longer rendered from the argument card.
RSpec.describe "Debate create page", type: :system, js: true do
  def dom_id(*args) = ActionView::RecordIdentifier.dom_id(*args)

  let(:root) { create(:hujah, body: "Should tabs beat spaces?") }
  let(:challenger) { create(:user, username: "challengerx") }
  let(:opponent) { create(:user, username: "opponentx") }
  let!(:argument) { create(:hujah, parent: root, user: opponent, vote: 3, body: "Spaces win, obviously") }

  it "links straight to the create page (no dialog), and creates the debate with rounds + opening argument" do
    login_as_system(challenger)
    visit "/hoojah/#{root.slug}"

    # The "Challenge to debate" affordance is now a plain link to the create page,
    # not a dialog trigger — no `dialog#open` round-trip.
    click_link "Challenge to debate"
    expect(page).to have_current_path(%r{/hoojah/#{root.slug}/debates/new})

    expect(page).to have_content("@opponentx")
    expect(page).to have_content("Should tabs beat spaces?")
    expect(page).to have_content("Spaces win, obviously")

    # Rounds picker: native radios, CSS-only selection, default 3.
    expect(page).to have_field("rounds_limit", with: "3", checked: true)
    choose("rounds_limit", option: "5", allow_label_click: true)

    # A stance opposing the argument's (Disagree, vote 3) must be picked.
    choose("challenger_stance", option: "1", allow_label_click: true) # Agree

    fill_in "Your opening argument", with: "Tabs are one keystroke."

    click_button "Send challenge"

    debate = Debate.last
    expect(debate.rounds_limit).to eq(5)
    expect(debate.opening_argument).to eq("Tabs are one keystroke.")
    expect(debate.challenger_stance).to eq(1)
    expect(debate).to be_pending

    expect(page).to have_current_path("/debates/#{debate.slug}")
  end
end
