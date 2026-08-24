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

  it "hides the Challenge affordance when the claim disallows debates" do
    claim = create(:hujah, allow_debates: false)
    replier = create(:user)
    claim.cast_vote(by: replier, choice: 3)
    create(:hujah, parent: claim, user: replier, vote: 3, body: "Counterpoint here friend")
    login_as_system(create(:user))
    visit hujah_path(claim.slug)

    expect(page).to have_content("Counterpoint here friend")
    expect(page).not_to have_text("Challenge")
  end

  it "still filters responses by stance" do
    author = create(:user)
    parent = create(:hujah, user: author)
    create(:hujah, user: author, parent: parent, vote: 1, body: "I agree strongly here")
    create(:hujah, user: author, parent: parent, vote: 3, body: "I disagree entirely here")
    visit hujah_path(parent.slug)

    within('[data-controller="response-filter"] [role="group"]') { click_button "Agree" }
    expect(find("a", text: "I agree strongly here")[:hidden]).to be_falsey
    expect(find("a", text: "I disagree entirely here", visible: :all)[:hidden]).to be_truthy
  end
end
