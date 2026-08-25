require "rails_helper"

# Cuprite (headless Chrome) system coverage for the profile screen. Runs in Phase 6.
RSpec.describe "Profile", type: :system, js: true do
  # Eager (`let!`) so the public profile at /u/rudz exists even in the examples
  # that never sign the user in (e.g. the anonymous-visitor case). A lazy `let`
  # left /u/rudz 404-ing whenever the example body didn't reference `user`.
  let!(:user) { create(:user, username: "rudz", full_name: "Rudz Rahman") }

  it "shows a public profile with the user's hoojahs" do
    create(:hujah, user: user, body: "my public take")
    visit "/u/rudz"
    expect(page).to have_content("@rudz")
    expect(page).to have_content("my public take")
  end

  it "hides the edit control from anonymous visitors" do
    visit "/u/rudz"
    expect(page).not_to have_selector("[aria-label='Edit your profile']")
  end

  it "lets the owner open the edit modal, save, and close it" do
    login_as_system(user)
    visit "/u/rudz"

    find("[aria-label='Edit your profile']").click
    dialog = find("dialog##{ActionView::RecordIdentifier.dom_id(user, :edit_dialog)}", visible: true)
    expect(dialog).to be_visible

    within(dialog) do
      fill_in "Headline", with: "Ships Hotwire"
      click_button "Save changes"
    end

    # update.turbo_stream.erb replaced the header (new headline) and fired
    # close_dialog (the native <dialog> is no longer open).
    expect(page).to have_content("Ships Hotwire")
    expect(page).to have_selector(
      "dialog##{ActionView::RecordIdentifier.dom_id(user, :edit_dialog)}:not([open])",
      visible: :all
    )
    expect(user.reload.headline).to eq("Ships Hotwire")
  end

  it "offers a photo file field on the edit form" do
    # The old client-side Cloudinary upload widget (an "Update photo" button + a
    # hidden user[photo] field) is gone; photo upload is now a plain multipart
    # file_field :avatar backed by ActiveStorage.
    login_as_system(user)
    visit "/u/rudz"
    find("[aria-label='Edit your profile']").click
    within("dialog##{ActionView::RecordIdentifier.dom_id(user, :edit_dialog)}") do
      expect(page).to have_field("user[avatar]", type: :file)
    end
  end
end
