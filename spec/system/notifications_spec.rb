require "rails_helper"

# Cuprite (headless Chrome) coverage for the notifications screen. Deleting a
# notification issues a DELETE via button_to; destroy.turbo_stream.erb removes the
# card in place (no full reload), so the row disappears from the list.
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

    within(card) { click_button "Delete notification" }

    expect(page).not_to have_selector(card)
    expect(Notification.exists?(notification.id)).to be(false)
  end

  it "shows the empty state when there are no notifications" do
    login_as_system(me)
    visit notifications_path
    expect(page).to have_content("You have no notifications")
  end
end
