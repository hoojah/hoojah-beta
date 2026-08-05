require "rails_helper"

# System coverage for compose/respond. Runs under cuprite in Phase 6 — created
# here per Task 2.1 Step 6 but NOT gated in this phase.
RSpec.describe "Compose", type: :system do
  let(:user) { create(:user) }

  it "composes a top-level hoojah and lands on it" do
    sign_in user
    visit new_hujah_path

    fill_in "What's your hoojah?", with: "Composed from a system test"
    click_button "Post hoojah"

    expect(page).to have_content("Composed from a system test")
    expect(page).to have_current_path(%r{/hoojah/})
  end

  it "responds to a hoojah with a stance and notifies the parent owner" do
    parent = create(:hujah, user: create(:user), body: "Parent claim")
    sign_in user
    visit respond_hujah_path(parent.slug)

    expect(page).to have_content("Post this response hoojah as:")
    fill_in "What's your hoojah?", with: "A neutral reply"
    choose(name: "hujah[vote]", option: "2", allow_label_click: true)
    click_button "Post hoojah"

    expect(page).to have_content("A neutral reply")
    reply = Hujah.find_by(body: "A neutral reply")
    expect(reply.parent_id).to eq(parent.id)
    expect(reply.vote).to eq([2]).or eq(2)
    expect(Notification.where(user: parent.user, category: "new_hoojah_response").count).to eq(1)
  end
end
