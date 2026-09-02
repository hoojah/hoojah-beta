require "rails_helper"

# Cuprite (headless Chrome) coverage for the Slice-3 inline stance-label editor.
RSpec.describe "Custom stance labels", type: :system, js: true do
  let(:author) { create(:user, username: "labeler") }

  it "lets an eligible author rename a stance inline and persists it on create" do
    create_list(:hujah, 10, user: author)
    login_as_system(author)
    visit new_hujah_path

    find("[data-stance-labels-target='word'][data-default='Agree']").click
    find("input[aria-label='Custom Agree label']").set("Yes")
    # Moving focus to the body commits the inline edit (blur handler) and swaps the
    # input back to a <span>, so we never touch the now-obsolete input node again.
    fill_in "What's your hoojah?", with: "a claim with renamed stances"
    expect(page).to have_css("[data-stance-labels-target='word']", text: "Yes")

    click_button "Post"

    h = Hujah.order(:created_at).last
    expect(h.agree_label).to eq("Yes")
    expect(h.neutral_label).to be_nil
    expect(h.disagree_label).to be_nil
  end

  it "shows a non-editable block to an ineligible author" do
    login_as_system(author) # zero prior posts → ineligible
    visit new_hujah_path

    expect(page).to have_css("div", text: "How people will weigh in")
    expect(page).to have_no_css("[data-controller='stance-labels']")
    expect(page).to have_no_css("[data-stance-labels-target='word']")
  end
end
