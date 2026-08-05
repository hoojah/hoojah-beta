require "rails_helper"

# Cuprite coverage for @mention rendering: a hoojah body containing @someuser
# renders a live link to that user's profile at /u/someuser.
RSpec.describe "Mention rendering", type: :system, js: true do
  it "renders an @mention in a hoojah body as a link to the profile" do
    author = create(:user)
    create(:user, username: "someuser")
    create(:hujah, user: author, body: "hey @someuser what do you think")

    visit "/"

    expect(page).to have_link("@someuser", href: "/u/someuser")
  end
end
