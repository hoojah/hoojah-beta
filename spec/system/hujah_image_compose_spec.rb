require "rails_helper"

# Slice 2: the full composer attaches ONE image via ActiveStorage DirectUpload. The :test
# service is Disk, so setting the hidden file input drives a real end-to-end direct upload
# in headless Chrome — the signed_id lands in hujah[image] and the POST attaches the blob.
RSpec.describe "Attaching an image to a new hujah", :js do
  let(:user) { create(:user) }
  before { sign_in user }

  it "attaches an image via the dialog and posts the hujah" do
    visit new_hujah_path
    fill_in "hujah[body]", with: "LRT3 will cut Klang Valley traffic more than any highway."

    click_button "Add image"
    expect(page).to have_text("up to 5 MB")

    # Drive the (hidden) device file input directly — Cuprite sets files via CDP even on a
    # display:none input, and dispatches the change that fires image-upload#fileChosen.
    find('[data-image-upload-target="fileInput"]', visible: :all)
      .set(Rails.root.join("spec/fixtures/files/test_image.png"))

    # DirectUpload finishes → attached state reveals, dialog closes.
    expect(page).to have_css('[data-image-upload-target="attached"]:not([hidden])', wait: 10)

    fill_in "hujah[image_alt]", with: "LRT3 train at Bandar Utama"
    click_button "Post"

    hujah = Hujah.order(:created_at).last
    expect(hujah.image).to be_attached
    expect(hujah.image_alt).to eq("LRT3 train at Bandar Utama")
  end
end
