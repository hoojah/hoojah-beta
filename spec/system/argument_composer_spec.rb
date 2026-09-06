require "rails_helper"

RSpec.describe "Argument composer", type: :system, js: true do
  it "is locked until the viewer votes, then lets them post an argument" do
    author = create(:user)
    h = create(:hujah, user: author, body: "Public transport should be fully free here")
    login_as_system(create(:user))
    visit hujah_path(h.slug)

    expect(page).to have_text("Vote to join the argument")

    find('[data-stance="agree"]').click # vote via the hero unlocks the composer

    find('[data-argument-composer-target="pill"]', wait: 5).click
    fill_in "hujah[body]", with: "Because fewer cars cleaner air"
    within('[data-argument-composer-target="expanded"]') { click_on "Send" }

    expect(page).to have_content("Because fewer cars cleaner air")
    expect(h.children.reload.map(&:body)).to include("Because fewer cars cleaner air")
  end

  it "gives a picked stance a filled state and carries the draft to the full-page composer" do
    author = create(:user)
    h = create(:hujah, user: author, body: "Public transport should be fully free here")
    replier = create(:user)
    h.cast_vote(by: replier, choice: 1) # already voted → composer unlocked
    login_as_system(replier)
    visit hujah_path(h.slug)

    find('[data-argument-composer-target="pill"]', wait: 5).click
    disagree = find('[data-argument-composer-target="stanceBtn"][data-stance="disagree"]')
    disagree.click
    # Visual feedback: the picked stance fills (bg-disagree) and reads as pressed.
    expect(disagree[:class]).to include("bg-disagree")
    expect(disagree["aria-pressed"]).to eq("true")

    find("[data-argument-composer-target='body']").set("A carried draft argument")
    # Maximize → full-page composer, draft (body + disagree stance) carried via ?body=/?vote=.
    find("a[aria-label='Open the full-page composer']").click

    expect(page).to have_field("hujah[body]", with: "A carried draft argument", wait: 5)
    expect(find('input[name="hujah[vote]"][value="3"]', visible: :all)).to be_checked
  end
end
