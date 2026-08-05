require "rails_helper"

# Cuprite (headless Chrome) coverage for Block (Slice 7). Drives the profile
# action: clicking Block flips the control to Unblock via Turbo Stream (no reload),
# and the blocked user's hoojah drops out of the global feed on the next load.
RSpec.describe "Block", type: :system, js: true do
  it "flips Follow→Unblock and removes the blocked user's hoojah from the feed" do
    me = create(:user)
    target = create(:user, username: "target")
    create(:hujah, user: target, body: "TARGET feed hoojah")

    login_as_system(me)

    # The blocked user's hoojah is visible in the global feed before the block.
    visit "/"
    expect(page).to have_content("TARGET feed hoojah")

    # Block from the target's profile — the control offers Block, then flips to
    # Unblock in place (create.turbo_stream.erb replaces the action button).
    visit "/u/target"
    expect(page).to have_button("Block")
    click_button "Block"
    expect(page).to have_button("Unblock")

    # On reload the feed excludes the now-blocked user's hoojah.
    visit "/"
    expect(page).not_to have_content("TARGET feed hoojah")
    expect(me.hidden_user_ids).to include(target.id)
  end
end
