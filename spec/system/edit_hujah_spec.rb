require "rails_helper"

# Cuprite (headless Chrome) coverage for the edit-a-hoojah flow. The "Edit hoojah"
# control lives in the show page's "More actions" menu, shown only while the body is
# editable. Clicking it opens the composer in edit mode; saving PATCHes the body and
# redirects back to the show page, which then renders the "· edited" marker.
RSpec.describe "Editing a hoojah", type: :system, js: true do
  let(:owner) { create(:user) }

  it "lets the owner edit within the window and shows an edited marker" do
    hujah = create(:hujah, user: owner, body: "My first take on teh tarik")
    login_as_system(owner)
    visit "/hoojah/#{hujah.slug}"

    find("summary[aria-label='More actions']").click
    click_link "Edit hoojah"

    expect(page).to have_content("Edit hoojah")
    fill_in "What's your hoojah?", with: "My revised take on teh tarik entirely"
    click_button "Save"

    expect(page).to have_content("My revised take on teh tarik entirely")
    expect(page).to have_content("edited")
  end

  it "hides the Edit affordance once a conviction has been cast" do
    locked = create(:hujah, user: owner, body: "A locked claim about roti", conviction_count: 1)
    login_as_system(owner)
    visit "/hoojah/#{locked.slug}"

    find("summary[aria-label='More actions']").click
    expect(page).not_to have_link("Edit hoojah")
    expect(page).to have_button("Delete hoojah")
  end
end
