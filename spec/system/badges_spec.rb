require "rails_helper"

# Cuprite coverage: a badge chip shows on the public profile once the user earns
# a badge. Reuses the Slice-3 login_as_system harness (the profile is public, so
# no login is strictly needed to view it — but the badge is earned by authoring).
RSpec.describe "Achievement badges", type: :system, js: true do
  it "shows the First Hoojah chip on the profile after the user earns it" do
    user = create(:user, username: "badger")
    # after_create_commit awards first_hoojah.
    create(:hujah, user: user, body: "my very first hoojah")

    visit "/u/badger"

    expect(page).to have_content("First Hoojah")
  end
end
