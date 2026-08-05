require "rails_helper"

# Cuprite (headless Chrome) coverage for the follow control on a public profile.
# Asserts the Turbo-Stream flip: after clicking Follow the button becomes
# "Following" and the follower-count chip increments — all in place, no reload.
RSpec.describe "Follow", type: :system, js: true do
  it "flips the button to Following and increments the count via Turbo Stream" do
    me = create(:user)
    target = create(:user, username: "target")
    login_as_system(me)
    visit "/u/target"

    # The Follow control renders for a signed-in non-owner; count starts at 0.
    within "##{ActionView::RecordIdentifier.dom_id(target, :follower_count)}" do
      expect(page).to have_content("0")
    end
    expect(page).to have_button("Follow")

    click_button "Follow"

    # create.turbo_stream.erb replaced the button (now Following) and the count
    # chip (now 1) without a full navigation — Capybara auto-waits for both.
    expect(page).to have_button("Following")
    within "##{ActionView::RecordIdentifier.dom_id(target, :follower_count)}" do
      expect(page).to have_content("1")
    end
    expect(target.followers).to include(me)
  end
end
