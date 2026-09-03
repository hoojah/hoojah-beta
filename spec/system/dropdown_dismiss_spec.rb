require "rails_helper"

# Cuprite (headless Chrome) coverage for dropdown_controller.js: the show page's
# share and more-actions menus are native <details> dropdowns, which natively toggle
# on their <summary> but stay open on an outside click. The controller closes them
# when the viewer taps anywhere outside the menu (or presses Escape), without touching
# the JS-off contract (the <summary> still opens/closes them on its own).
#
# Assert on the `<details open>` attribute, not on link visibility: a *closed* details
# still leaves its children in the DOM, and Cuprite's visible-text check reports them
# inconsistently. The open attribute is the unambiguous "is the menu showing" signal.
RSpec.describe "Dropdown dismissal", type: :system, js: true do
  let(:author) { create(:user, username: "author") }
  let(:hujah) { create(:hujah, user: author, body: "Dismiss my menus") }

  it "closes the share menu when tapping outside it" do
    visit "/hoojah/#{hujah.slug}"

    find("summary[aria-label='Share this hoojah']").click
    expect(page).to have_css("details[data-controller~='share'][open]")

    # A click on the claim body — outside the menu — dismisses it.
    find("h1.hujah-body").click
    expect(page).to have_no_css("details[data-controller~='share'][open]")
  end

  it "closes the more-actions menu when tapping outside it" do
    login_as_system(author)
    visit "/hoojah/#{hujah.slug}"

    find("summary[aria-label='More actions']").click
    expect(page).to have_button("Delete hoojah")
    expect(page).to have_css("details[data-controller='dropdown'][open]")

    find("h1.hujah-body").click
    expect(page).to have_no_css("details[data-controller='dropdown'][open]")
  end
end
