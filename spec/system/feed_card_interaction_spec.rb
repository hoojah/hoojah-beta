require "rails_helper"

RSpec.describe "Feed card interaction", type: :system, js: true do
  it "does not wrap the body in a link but keeps hashtags and mentions clickable" do
    create(:user, username: "sitir")
    author = create(:user)
    create(:hujah, user: author, body: "free transit for #kl and @sitir by 2030")
    login_as_system(create(:user))
    visit "/"
    card = find("[data-testid='hujah-card']", match: :first)
    expect(card).to have_css(".hujah-body")
    expect(card).to have_no_css("a.hujah-body, a > .hujah-body")
    within(card) do
      expect(page).to have_link("#kl")
      expect(page).to have_link("@sitir")
    end
  end

  it "shows Jump in on a plain card linking to the thread, and the conviction count when > 0" do
    author = create(:user)
    h = create(:hujah, user: author, body: "a plain claim about kopi", conviction_count: 2)
    login_as_system(create(:user))
    visit "/"
    card = find("[data-testid='hujah-card']", match: :first)
    within(card) do
      expect(page).to have_link("Jump in", href: hujah_path(h.slug))
      expect(page).to have_text("2")
    end
  end

  it "points Jump in at the debate room when a live debate exists" do
    author = create(:user)
    opp = create(:user)
    h = create(:hujah, user: author, body: "a debated claim about durian")
    debate = create(:debate, hujah: h, challenger: author, opponent: opp, status: :active)
    login_as_system(create(:user))
    visit "/"
    card = find("[data-testid='hujah-card']", match: :first)
    within(card) { expect(page).to have_link("Jump in", href: debate_path(debate.slug)) }
  end
end
