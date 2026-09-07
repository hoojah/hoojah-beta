require "rails_helper"

# The profile-edit avatar uploader reuses the composer's image_upload controller INLINE
# (no nested <dialog>): a hidden file input drives a real end-to-end ActiveStorage
# DirectUpload in headless Chrome (the :test service is Disk), the signed_id lands in
# user[avatar], and the PATCH attaches the blob. Mirrors hujah_image_compose_spec.
RSpec.describe "Uploading a profile avatar", type: :system, js: true do
  let!(:user) { create(:user, username: "rudz", full_name: "Rudz Rahman") }

  it "attaches an avatar via the inline uploader and saves the profile" do
    login_as_system(user)
    visit "/u/rudz"

    find("[aria-label='Edit your profile']").click
    dialog = find("dialog##{ActionView::RecordIdentifier.dom_id(user, :edit_dialog)}", visible: true)
    expect(dialog).to be_visible

    # Drive the (hidden) device file input directly — Cuprite sets files via CDP even on a
    # display:none input, and dispatches the change that fires image-upload#fileChosen.
    within(dialog) do
      find('[data-image-upload-target="fileInput"]', visible: :all)
        .set(Rails.root.join("spec/fixtures/files/test_image.png"))

      # DirectUpload finishes -> attached (circular preview) state reveals, inline.
      expect(page).to have_css('[data-image-upload-target="attached"]:not([hidden])', wait: 10)

      click_button "Save changes"
    end

    # update.turbo_stream.erb replaced the header and fired close_dialog.
    expect(page).to have_selector(
      "dialog##{ActionView::RecordIdentifier.dom_id(user, :edit_dialog)}:not([open])",
      visible: :all
    )
    expect(user.reload.avatar).to be_attached
  end
end
