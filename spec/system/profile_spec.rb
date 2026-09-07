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

  # Issue #13: the navbar avatar tile shows gradient INITIALS derived from the name
  # (variant: :tile), so a full_name change must refresh it live via Turbo Stream —
  # without a full page navigation. Rudz Rahman -> Zoe Kingman flips "RR" to "ZK".
  it "refreshes the navbar avatar initials after a profile update, no reload" do
    login_as_system(user)
    visit "/u/rudz"

    nav_avatar = "##{ActionView::RecordIdentifier.dom_id(user, :nav_avatar)}"
    expect(page).to have_selector("#{nav_avatar} [aria-label='Rudz Rahman']")

    find("[aria-label='Edit your profile']").click
    within("dialog##{ActionView::RecordIdentifier.dom_id(user, :edit_dialog)}") do
      fill_in "Full name", with: "Zoe Kingman"
      click_button "Save changes"
    end

    # The navbar tile now carries the new name/initials, streamed in place.
    expect(page).to have_selector("#{nav_avatar} [aria-label='Zoe Kingman']")
    expect(page).to have_no_selector("#{nav_avatar} [aria-label='Rudz Rahman']")
    expect(user.reload.full_name).to eq("Zoe Kingman")
  end

  it "offers an inline avatar uploader on the edit form" do
    # Photo upload is now the inline image_upload widget (chooser -> live preview ->
    # DirectUpload) reused from the composer: a hidden user[avatar] signed-id field the
    # background upload fills, a hidden file input, and a "Change photo" chooser button.
    login_as_system(user)
    visit "/u/rudz"
    find("[aria-label='Edit your profile']").click
    within("dialog##{ActionView::RecordIdentifier.dom_id(user, :edit_dialog)}") do
      expect(page).to have_field("user[avatar]", type: :hidden)
      expect(page).to have_css('[data-image-upload-target="fileInput"]', visible: :all)
      expect(page).to have_button("Change photo")
    end
  end
end
