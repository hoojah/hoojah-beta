require "rails_helper"

# Cuprite (headless Chrome) coverage for the change-visibility flow (Slice 2). The
# "Change visibility" control lives in the show page's "More actions" menu, shown only
# to a top-level owner while the hoojah is not moderation-removed. Following its link
# lands on the change form; for a TIGHTENING target that same page doubles as the
# destructive confirmation screen (typed-confirm word → permanent purge).
#
# Login is `login_as_system` (Warden re-auth hook), not the real /login form: a real
# credential POST is rejected in this suite (see spec/support/devise.rb).
RSpec.describe "Change visibility flow", type: :system, js: true do
  let(:owner) { create(:user, username: "owner") }
  let(:stranger) { create(:user, username: "stranger") }

  it "lets the owner tighten a public claim after typing the confirm word" do
    hujah = create(:hujah, user: owner, visibility: :visible_public, body: "System-spec claim body")
    hujah.cast_vote(by: stranger, choice: 1)

    login_as_system(owner)
    visit "/hoojah/#{hujah.slug}/visibility?to=private_only"
    expect(page).to have_content("permanently removes")
    fill_in "confirm", with: "REMOVE"
    click_button "Tighten visibility permanently"

    expect(page).to have_current_path("/hoojah/#{hujah.slug}")
    expect(hujah.reload.visibility).to eq("private_only")
    expect(Vote.exists?(hujah_id: hujah.id, user_id: stranger.id)).to be(false)
  end

  it "shows the Change visibility menu item only to a top-level owner" do
    hujah = create(:hujah, user: owner, visibility: :visible_public, body: "Menu-visibility claim")
    login_as_system(owner)
    visit "/hoojah/#{hujah.slug}"

    find("summary[aria-label='More actions']").click
    expect(page).to have_link("Change visibility")
  end
end
