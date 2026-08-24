require "rails_helper"

RSpec.describe "Single hoojah", type: :system, js: true do
  it "renders the claim hero with a tag chip linking to the tag feed" do
    h = create(:hujah, body: "Free transit in every #KlangValley city please now")
    visit hujah_path(h.slug)
    expect(page).to have_link("#KlangValley", href: tag_path("klangvalley"))
  end

  it "keeps the share menu and more-actions menu reachable in the header" do
    h = create(:hujah, body: "A claim worth reading about transit here")
    visit hujah_path(h.slug)
    expect(page).to have_selector("summary[aria-label='Share this hoojah']")
    expect(page).to have_selector("summary[aria-label='More actions']")
  end
end
