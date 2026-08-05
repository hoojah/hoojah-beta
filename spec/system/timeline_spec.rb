require "rails_helper"

# Cuprite coverage for the Following feed. A signed-in user who follows someone
# sees their own + the followed user's hoojahs under the Following tab, and not a
# stranger's.
RSpec.describe "Following timeline", type: :system, js: true do
  it "shows own and followed content under the Following tab, not strangers'" do
    me = create(:user)
    followed = create(:user)
    stranger = create(:user)
    me.active_follows.create!(followed: followed, status: :accepted)
    create(:hujah, user: me, body: "my own take")
    create(:hujah, user: followed, body: "a followed take")
    create(:hujah, user: stranger, body: "a stranger take")

    login_as_system(me)
    visit "/"
    click_link "Following"

    expect(page).to have_content("my own take")
    expect(page).to have_content("a followed take")
    expect(page).to have_no_content("a stranger take")
  end
end
