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
end
