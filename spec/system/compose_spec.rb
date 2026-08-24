require "rails_helper"

# System coverage for compose/respond. Runs under cuprite in Phase 6 — created
# here per Task 2.1 Step 6 but NOT gated in this phase.
RSpec.describe "Compose", type: :system do
  let(:user) { create(:user) }

  it "composes a top-level hoojah and lands on it" do
    sign_in user
    visit new_hujah_path

    fill_in "What's your hoojah?", with: "Composed from a system test"
    click_button "Post"

    expect(page).to have_content("Composed from a system test")
    expect(page).to have_current_path(%r{/hoojah/})
  end

  # JS-off (rack_test, no JS): the native <select> is the canonical visibility control,
  # so a user can still pick Private without JavaScript — the old hidden field always
  # shipped Public here. Guards the FIX 2 regression.
  it "posts a non-public visibility with JS off via the native select" do
    sign_in user
    visit new_hujah_path

    fill_in "What's your hoojah?", with: "A JS-off private claim about transit"
    select "Private", from: "hujah[visibility]"
    click_button "Post"

    expect(Hujah.order(:created_at).last.visibility).to eq "private_only"
  end

  it "responds to a hoojah with a stance and notifies the parent owner" do
    parent = create(:hujah, user: create(:user), body: "Parent claim")
    # 2026 vote-to-respond gate (Task 2.6): the replier must vote on the parent first.
    parent.cast_vote(by: user, choice: 1)
    sign_in user
    visit respond_hujah_path(parent.slug)

    expect(page).to have_content("Post this response hoojah as:")
    fill_in "What's your hoojah?", with: "A neutral reply"
    choose(name: "hujah[vote]", option: "2", allow_label_click: true)
    click_button "Post"

    expect(page).to have_content("A neutral reply")
    reply = Hujah.find_by(body: "A neutral reply")
    expect(reply.parent_id).to eq(parent.id)
    expect(reply.vote).to eq([2]).or eq(2)
    expect(Notification.where(user: parent.user, category: "new_hoojah_response").count).to eq(1)
  end
end
