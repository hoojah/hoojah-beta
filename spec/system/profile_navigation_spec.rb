require "rails_helper"

# Regression: profile-tab content lives inside `turbo_frame_tag "profile-list"`
# (users/show.html.erb). Without `target: "_top"` on the frame, clicking any card
# inside it — a hoojah card (→ /hoojah/:slug), a debate card (→ /debates/:slug),
# an author byline (→ /u/:username), or the empty-state CTA — asks Turbo for a
# matching `profile-list` frame on the destination page, which has none, so Turbo
# renders "Content missing" instead of navigating. The frame now carries
# `target: "_top"`, so links inside it perform full-page visits — while the tab
# links keep their explicit `data: {turbo_frame: "profile-list"}`, which
# overrides the frame default and still swaps only the frame. Same bug/fix
# pattern as spec/system/trending_navigation_spec.rb.
RSpec.describe "Profile navigation", type: :system, js: true do
  let!(:user) { create(:user, username: "rudz", full_name: "Rudz Rahman") }

  it "navigates full-page from a Hoojahs-tab card to the hoojah show page" do
    hujah = create(:hujah, user: user, body: "a profile card claim about nasi lemak")

    login_as_system(create(:user))
    visit "/u/rudz"

    within "turbo-frame#profile-list" do
      expect(page).to have_content("a profile card claim about nasi lemak")
      find("a[href='#{hujah_path(hujah.slug)}']").click
    end

    expect(page).to have_current_path(hujah_path(hujah.slug))
    expect(page).not_to have_text("Content missing")
    expect(page).to have_content("a profile card claim about nasi lemak")
  end

  it "still swaps only the frame on a tab click, then navigates full-page from a debate card" do
    hoojah = create(:hujah, user: user, body: "public transport should be free")
    opponent = create(:user, username: "sitir")
    # DebatePolicy::Scope (the profile Debates tab) shows an ACTIVE debate only to a
    # participant; an unrelated logged-in viewer sees a debate here only once it is
    # CONCLUDED (both participants public, no blocks). Status is immaterial to the
    # navigation this spec guards — the debate card links to /debates/:slug either way.
    debate = create(:debate, hujah: hoojah, challenger: user, opponent: opponent, status: :concluded)

    login_as_system(create(:user))
    visit "/u/rudz"

    find("[data-testid='profile-tab-debates']").click
    within "turbo-frame#profile-list" do
      expect(page).to have_link(href: debate_path(debate.slug))
    end
    expect(page).to have_current_path("/u/rudz")

    # The active pill must FOLLOW the click — the whole point of rendering the tab bar
    # inside the profile-list frame. Asserting only that the list swapped (above) passed
    # even when the tab bar was frozen outside the frame, so pin the highlight itself.
    debates_tab = find("[data-testid='profile-tab-debates']")
    expect(debates_tab["aria-current"]).to eq("page")
    expect(debates_tab[:class]).to include("bg-primary")
    expect(find("[data-testid='profile-tab-hoojahs']")["aria-current"]).to be_nil

    within "turbo-frame#profile-list" do
      find("a[href='#{debate_path(debate.slug)}']").click
    end

    expect(page).to have_current_path(debate_path(debate.slug))
    expect(page).not_to have_text("Content missing")
  end
end
