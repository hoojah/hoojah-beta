require "rails_helper"

# Cuprite (headless Chrome) coverage for the end-to-end moderator remove flow (2026
# moderation). A flagged hujah sits in the /moderation queue; a moderator removes it,
# accepting the turbo_confirm, and the item leaves the queue in place via Turbo Stream
# (no reload). A member then no longer sees the hujah in the feed, and its direct URL
# bounces back to the feed (HujahPolicy#show? → Pundit rescue → redirect to root).
#
# The "Not allowed." flash the rescue sets is asserted at the request level
# (spec/requests/moderation_visibility_spec.rb) — this app deliberately renders no flash
# region in the layout, so a browser assertion here proves the REDIRECT, not the toast.
RSpec.describe "Moderation remove flow", type: :system, js: true do
  include ActionView::RecordIdentifier

  it "removes a flagged hujah from the queue in place and hides it from members" do
    author = create(:user)
    member = create(:user)
    moderator = create(:user, :moderator)
    hujah = create(:hujah, user: author, body: "SYSTEM removable claim")
    create(:flag, user: member, hujah: hujah, subject: :spam)

    login_as_system(moderator)
    visit "/moderation"

    item = "##{dom_id(hujah, :moderation_item)}"
    expect(page).to have_css(item)
    expect(page).to have_content("SYSTEM removable claim")

    # button_to DELETE with data-turbo-confirm → native window.confirm → accept it.
    accept_confirm do
      within(item) { click_button "Remove" }
    end

    # remove.turbo_stream.erb removes the item and refreshes the count — no page reload.
    expect(page).to have_no_css(item)
    expect(hujah.reload).to be_moderation_removed

    # A member's feed excludes the removed hujah, and its direct URL bounces to the feed.
    login_as_system(member)
    visit "/"
    expect(page).not_to have_content("SYSTEM removable claim")

    visit "/hoojah/#{hujah.slug}"
    expect(page).to have_current_path(root_path)
    expect(page).not_to have_content("SYSTEM removable claim")
  end
end
