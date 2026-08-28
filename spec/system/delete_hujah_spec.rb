require "rails_helper"

# Cuprite (headless Chrome) coverage for the delete-a-hoojah flow. The control lives
# inside the show page's "More actions" <details> menu; it is a button_to DELETE with
# a data-turbo-confirm, so clicking it fires a native window.confirm. Accepting it
# posts DELETE /hoojah/:slug, which (for a clean, leaf hoojah) destroys the record and
# redirects to the feed — Turbo follows the redirect, so the browser lands on root.
RSpec.describe "Deleting a hoojah", type: :system, js: true do
  let(:owner) { create(:user) }
  let(:hujah) { create(:hujah, user: owner, body: "A claim worth deleting") }

  it "deletes the owner's clean hoojah from the More actions menu and returns to the feed" do
    login_as_system(owner)
    visit "/hoojah/#{hujah.slug}"

    find("summary[aria-label='More actions']").click

    # button_to DELETE with data-turbo-confirm → native window.confirm → accept it.
    accept_confirm do
      click_button "Delete hoojah"
    end

    expect(page).to have_current_path(root_path)
    expect(page).not_to have_content("A claim worth deleting")
    expect(Hujah.exists?(hujah.id)).to be(false)
  end
end
