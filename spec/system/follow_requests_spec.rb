require "rails_helper"

# Cuprite (headless Chrome) coverage for the pending follow-requests inbox
# (2026 follow gaps). A private user reaches the inbox from the user dropdown
# (which shows a "(N)" count), then accepts one request and declines the other.
#
# Task 6 flow: accept/decline respond with turbo_stream, so each acted-on row is
# removed IN PLACE (no navigation) and the dropdown count chip updates live —
# ticking down to "(1)" after the accept, then vanishing once the last request is
# declined and the list swaps to its empty state.
RSpec.describe "Follow requests inbox", type: :system, js: true do
  it "accepts one and declines the other in place, updating the dropdown count" do
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

    # Accept alice's request — the row disappears in place and the count ticks to (1).
    # (The chip lives inside the closed dropdown, so match it with visible: :all — the
    # turbo update still reaches it; the request spec pins the count string directly.)
    within "##{ActionView::RecordIdentifier.dom_id(accepted, :request)}" do
      click_button "Accept"
    end
    expect(page).not_to have_content("@alice")
    expect(page).to have_content("@bob")
    expect(page).to have_selector("#nav-follow-requests-count", text: "(1)", visible: :all)

    # Decline bob's remaining request → the count chip disappears and the list
    # swaps to its empty state, all without navigating away.
    click_button "Decline"
    expect(page).to have_content("No pending follow requests")
    expect(page).not_to have_selector("#nav-follow-requests-count", visible: :all)

    # Alice (accepted) is now a follower; bob (declined) is not.
    expect(me.reload.followers).to include(alice)
    expect(me.followers).not_to include(bob)

    visit user_followers_path(me.username)
    expect(page).to have_content("@alice")
    expect(page).not_to have_content("@bob")
  end
end
