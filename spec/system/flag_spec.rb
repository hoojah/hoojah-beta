require "rails_helper"

# Cuprite (headless Chrome) coverage for the flag flow. The flag control lives
# inside the show page's "More actions" <details> menu; clicking a reason posts
# to POST /hoojah/:slug/flags, which returns create.turbo_stream.erb — that fires
# the custom `close_dialog` Turbo action and swaps the trigger for a confirmation.
RSpec.describe "Flagging a hoojah", type: :system, js: true do
  let(:author) { create(:user) }
  let(:flagger) { create(:user) }
  let(:hujah) { create(:hujah, user: author, body: "A claim worth flagging") }

  it "opens the flag dialog and, on submit, closes it and confirms in place" do
    login_as_system(flagger)
    visit "/hoojah/#{hujah.slug}"

    # Open the "More actions" menu, then the flag dialog.
    find("summary[aria-label='More actions']").click
    click_button "Flag this hoojah"

    dialog = find("dialog##{ActionView::RecordIdentifier.dom_id(hujah, :flag_dialog)}", visible: true)
    expect(dialog).to be_visible

    within(dialog) { click_button "It's suspicious or spam" }

    # create.turbo_stream.erb fires close_dialog and then replaces the flag_control
    # wrapper (which contains the dialog) with an in-place confirmation — so the
    # dialog is gone entirely and the confirmation is shown.
    expect(page).to have_content("Hoojah flagged. Thank you.")
    expect(page).to have_no_selector(
      "dialog##{ActionView::RecordIdentifier.dom_id(hujah, :flag_dialog)}",
      visible: :all
    )

    flag = Flag.last
    expect(flag.hujah_id).to eq(hujah.id)
    expect(flag.user_id).to eq(flagger.id)
    expect(flag.subject).to eq("spam")
  end

  # Slice 5: the two image-specific reasons are additive and conditional — they exist
  # in the dialog only when the hoojah carries a visible image, and never disturb the
  # three frozen reasons above.
  it "offers image reasons only when the hoojah has a visible image" do
    hujah.image.attach(
      io: Rails.root.join("spec/fixtures/files/test_image.png").open,
      filename: "t.png", content_type: "image/png"
    )
    login_as_system(flagger)
    visit "/hoojah/#{hujah.slug}"

    find("summary[aria-label='More actions']").click
    click_button "Flag this hoojah"

    dialog = find("dialog##{ActionView::RecordIdentifier.dom_id(hujah, :flag_dialog)}", visible: true)
    within(dialog) do
      expect(page).to have_button("The image is graphic or explicit")
      expect(page).to have_button("The image isn't theirs to post")
      # the three frozen reasons are still present and untouched
      expect(page).to have_button("It's suspicious or spam")
    end
  end

  it "hides the image reasons when the hoojah has no image" do
    login_as_system(flagger)
    visit "/hoojah/#{hujah.slug}"

    find("summary[aria-label='More actions']").click
    click_button "Flag this hoojah"

    dialog = find("dialog##{ActionView::RecordIdentifier.dom_id(hujah, :flag_dialog)}", visible: true)
    within(dialog) do
      expect(page).to have_no_button("The image is graphic or explicit")
      expect(page).to have_no_button("The image isn't theirs to post")
    end
  end
end
