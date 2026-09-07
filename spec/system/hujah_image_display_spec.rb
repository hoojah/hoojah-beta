require "rails_helper"

# Slice 3: the attached image renders 16:9 below the claim on the single-hujah page,
# in the :shown state (tappable — the lightbox itself lands in Slice 4) or the :held
# state (a pending image-subject flag soft-holds it behind a per-viewer reveal).
RSpec.describe "Hujah image display", :js do
  let(:hujah) do
    h = create(:hujah, image_alt: "a train")
    h.image.attach(
      io: Rails.root.join("spec/fixtures/files/test_image.png").open,
      filename: "t.png", content_type: "image/png"
    )
    h
  end

  it "shows the image on the single page with the author's alt text" do
    visit hujah_path(hujah)
    expect(page).to have_css('img[alt="a train"]')
  end

  it "falls back to a generic alt when the author left it blank" do
    hujah.update!(image_alt: nil)
    visit hujah_path(hujah)
    expect(page).to have_css('img[alt="Image attached to this hoojah"]')
  end

  it "holds the image behind a veil when a pending image flag exists" do
    create(:flag, hujah: hujah, subject: :image_graphic) # status defaults to pending
    visit hujah_path(hujah)

    expect(page).to have_text("Image hidden while we review a report")
    expect(page).to have_text("The claim stays votable. Only the image is held.")
    expect(page).to have_button("Show anyway")

    # Per-viewer reveal: the image starts hidden, "Show anyway" flips it in locally.
    expect(page).to have_css('[data-image-reveal-target="image"][hidden]', visible: :all)
    click_button "Show anyway"
    expect(page).to have_css('[data-image-reveal-target="image"]:not([hidden])')
  end
end
