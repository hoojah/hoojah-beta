require "rails_helper"

# Cuprite (headless Chrome) coverage for the Hoojah 2026 profile redesign: the
# gradient header, the conviction card, and the live-debate card (Phase 4.4),
# plus the Hoojahs/Responses/Debates count tabs (Phase 4.5).
RSpec.describe "Profile redesign", type: :system, js: true do
  let!(:user) { create(:user, username: "rudz", full_name: "Rudz Rahman") }

  it "renders the gradient hero with avatar, name, handle and the settings gear for the owner" do
    login_as_system(user)
    visit "/u/rudz"

    expect(page).to have_selector(".profile-hero")
    expect(page).to have_content("Rudz Rahman")
    expect(page).to have_content("@rudz")
    expect(page).to have_selector("[aria-label='Edit your profile']")
  end

  it "hides the settings gear and shows a Follow pill for a signed-in non-owner" do
    other = create(:user, username: "viewer9")
    login_as_system(other)
    visit "/u/rudz"

    expect(page).not_to have_selector("[aria-label='Edit your profile']")
    expect(page).to have_button("Follow")
  end

  it "opens the existing owner edit dialog from the settings gear" do
    login_as_system(user)
    visit "/u/rudz"

    find("[aria-label='Edit your profile']").click
    dialog = find("dialog##{ActionView::RecordIdentifier.dom_id(user, :edit_dialog)}", visible: true)
    expect(dialog).to be_visible
  end

  it "shows the conviction card with real vote counts and no gamified metrics" do
    hujah = create(:hujah)
    create(:vote, user: user, hujah: hujah, vote: [1])
    login_as_system(user)
    visit "/u/rudz"

    within("[data-testid='conviction-card']") do
      expect(page).to have_content("1")
    end
    expect(page).not_to have_content("Lvl")
    expect(page).not_to have_content("streak")
  end

  it "shows a live-debate card for the owner's active debate to an unrelated visitor" do
    hoojah = create(:hujah, user: user, body: "public transport should be free")
    opponent = create(:user, username: "sitir9")
    debate = create(:debate, hujah: hoojah, challenger: user, opponent: opponent, status: :active)
    stranger = create(:user, username: "stranger9")
    login_as_system(stranger)
    visit "/u/rudz"

    expect(page).to have_link(href: "/debates/#{debate.slug}")
    expect(page).to have_content("@sitir9")
  end

  it "leak check: hides the live-debate card when the other participant is private and unfollowed" do
    hoojah = create(:hujah, user: user, body: "public transport should be free")
    private_opp = create(:user, username: "privateopp9", private: true)
    create(:debate, hujah: hoojah, challenger: user, opponent: private_opp, status: :active)
    stranger = create(:user, username: "stranger10")
    login_as_system(stranger)
    visit "/u/rudz"

    expect(page).not_to have_content("@privateopp9")
    expect(page).not_to have_selector("a[href*='/debates/']")
  end

  # ── Hoojah 2026, Phase 4.5: profile count tabs ──────────────────────────────
  describe "the profile count tabs" do
    it "shows the three tabs with counts, hoojahs active by default" do
      create(:hujah, user: user, body: "tab default claim")
      login_as_system(user)
      visit "/u/rudz"

      expect(page).to have_selector("turbo-frame#profile-list")
      expect(page).to have_selector("[data-testid='profile-tab-hoojahs']")
      expect(page).to have_selector("[data-testid='profile-tab-responses']")
      expect(page).to have_selector("[data-testid='profile-tab-debates']")
      expect(page).to have_content("tab default claim")
    end

    it "switches to the responses list when the Responses tab is clicked" do
      parent = create(:hujah)
      create(:hujah, user: user, parent: parent, body: "tab reply body for system spec")
      login_as_system(user)
      visit "/u/rudz"

      find("[data-testid='profile-tab-responses']").click
      expect(page).to have_content("tab reply body for system spec")
    end
  end
end
