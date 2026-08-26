require "rails_helper"

# Cuprite (headless Chrome) coverage for the notifications screen. Deleting a
# notification issues a DELETE via button_to; destroy.turbo_stream.erb removes the
# card in place (no full reload), so the row disappears from the list.
#
# Task 4.2 moved the trash control off the row into a "More options" overflow
# (`<details>` + `ui/_menu`), so opening it is now a required first step before the
# Delete button is clickable — mirrors the existing idiom (share_spec/flag_spec
# open their own `<details>` the same way before clicking inside it).
RSpec.describe "Notifications", type: :system, js: true do
  let(:me) { create(:user) }

  it "removes a notification card in place via Turbo Stream" do
    subject_user = create(:user, username: "replier")
    hujah = create(:hujah, user: me)
    notification = create(:notification,
      user: me,
      hujah: hujah,
      subject_user: subject_user,
      category: :new_hoojah_response)

    login_as_system(me)
    visit notifications_path

    card = "##{ActionView::RecordIdentifier.dom_id(notification)}"
    expect(page).to have_selector(card)
    expect(page).to have_content("@replier posted a new argument on your hoojah")

    within(card) do
      find("summary[aria-label='More options']").click
      click_button "Delete notification"
    end

    expect(page).not_to have_selector(card)
    expect(Notification.exists?(notification.id)).to be(false)
  end

  it "accepts a follow request from its notification card, removing it in place" do
    # A private user with an incoming request: creating the pending follow fires the
    # follow_request notification whose card carries Accept/Decline (Task 6 makes
    # them respond with turbo_stream, so the card vanishes without a reload).
    me_private = create(:user, private: true)
    requester = create(:user, username: "asker")
    requester.active_follows.create!(followed: me_private, status: :pending)
    notification = Notification.find_by(user: me_private, subject_user: requester, category: :follow_request)

    login_as_system(me_private)
    visit notifications_path

    card = "##{ActionView::RecordIdentifier.dom_id(notification)}"
    expect(page).to have_selector(card)
    expect(page).to have_content("@asker requested to follow you")

    within(card) { click_button "Accept" }

    expect(page).not_to have_selector(card)
    expect(me_private.reload.followers).to include(requester)
  end

  it "shows the empty state when there are no notifications" do
    login_as_system(me)
    visit notifications_path
    expect(page).to have_content("You have no notifications")
  end
end
