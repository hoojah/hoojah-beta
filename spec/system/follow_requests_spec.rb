require "rails_helper"

# Cuprite (headless Chrome) coverage for the pending follow-requests inbox
# (2026 follow gaps). A private user reaches the inbox from the user dropdown
# (which shows a "(N)" count), then accepts one request and declines the other.
#
# This runs the CURRENT redirect_back flow: accept/decline are button_to's that
# reload the inbox each time. Task 6 upgrades both to turbo_stream (in place);
# when it lands this spec still holds — the row is gone and the empty state
# eventually shows either way.
RSpec.describe "Follow requests inbox", type: :system, js: true do
  it "lists pending requests, accepts one and declines the other" do
    me = create(:user, private: true, username: "owner")
    alice = create(:user, username: "alice")
    bob = create(:user, username: "bob")
    accepted = alice.active_follows.create!(followed: me, status: :pending)
    bob.active_follows.create!(followed: me, status: :pending)

    login_as_system(me)
    visit root_path

    # The user dropdown surfaces the pending count.
    find("nav details summary").click
    expect(page).to have_link("Follow requests")
    expect(page).to have_selector("#nav-follow-requests-count", text: "(2)")

    click_link "Follow requests"

    expect(page).to have_content("@alice")
    expect(page).to have_content("@bob")

    # Accept alice's request.
    within "##{ActionView::RecordIdentifier.dom_id(accepted, :request)}" do
      click_button "Accept"
    end
    expect(page).not_to have_content("@alice")

    # Decline bob's remaining request → empty state.
    click_button "Decline"
    expect(page).to have_content("No pending follow requests")

    # Alice (accepted) is now a follower; bob (declined) is not.
    expect(me.reload.followers).to include(alice)
    expect(me.followers).not_to include(bob)

    visit user_followers_path(me.username)
    expect(page).to have_content("@alice")
    expect(page).not_to have_content("@bob")
  end
end
