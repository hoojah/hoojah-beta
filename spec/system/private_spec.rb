require "rails_helper"

# Cuprite (headless Chrome) end-to-end for Slice 7b (Private Accounts). Drives the
# whole gate: an owner turns their account private from the profile editor → a
# stranger who visits sees only the gated header (no hoojahs) and can request to
# follow → the owner accepts the request from their notifications → the stranger
# now sees the previously-hidden content. Reuses the persistent-login harness
# (login_as_system) and switches the acting user mid-flow.
RSpec.describe "Private accounts", type: :system, js: true do
  it "gates a private profile from a stranger and reveals it once the request is accepted" do
    owner = create(:user, username: "owner", full_name: "Owner Name")
    create(:hujah, user: owner, body: "SECRET private take")
    requester = create(:user, username: "req", full_name: "Req Person")

    # 1) The owner makes their account private via the profile editor.
    login_as_system(owner)
    visit "/u/owner"
    find("[aria-label='Edit your profile']").click
    dialog = find("dialog##{ActionView::RecordIdentifier.dom_id(owner, :edit_dialog)}", visible: true)
    within(dialog) do
      check "user[private]"
      click_button "Save changes"
    end
    # The header refreshes in place; the owner still sees their own content.
    expect(page).to have_content("SECRET private take")
    expect(owner.reload).to be_private

    # 2) A stranger sees the gated header only — no hoojah list — and can request.
    login_as_system(requester)
    visit "/u/owner"
    expect(page).to have_content("This account is private")
    expect(page).to have_no_content("SECRET private take")
    click_button "Follow"
    expect(page).to have_button("Requested")

    # 3) The owner accepts the pending request from their notifications.
    login_as_system(owner)
    visit "/notifications"
    expect(page).to have_content("requested to follow you")
    click_button "Accept"
    expect(owner.followers.reload).to include(requester)

    # 4) The requester, now an accepted follower, sees the previously-hidden content.
    login_as_system(requester)
    visit "/u/owner"
    expect(page).to have_content("SECRET private take")
  end
end
