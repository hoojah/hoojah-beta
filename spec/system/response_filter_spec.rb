require "rails_helper"

# The response filter is pure client-side show/hide (response_filter_controller.js):
# clicking a stance tab hides child cards of other stances via the `hidden` attribute
# and reflects the active tab through aria-pressed. No fetch, no re-render.
RSpec.describe "Response filter", type: :system, js: true do
  it "hides non-matching responses and reflects the active tab via aria-pressed" do
    author = create(:user)
    parent = create(:hujah, user: author)
    create(:hujah, user: author, parent: parent, vote: 1, body: "I agree strongly")
    create(:hujah, user: author, parent: parent, vote: 3, body: "I disagree entirely")

    visit "/hoojah/#{parent.slug}"

    # All responses visible under the default "All" tab.
    expect(page).to have_content("I agree strongly")
    expect(page).to have_content("I disagree entirely")

    # Scope to the filter group — the vote-bar buttons also expose aria-label "Agree".
    within('[data-controller="response-filter"] [role="group"]') { click_button "Agree" }

    agree_item = find("a", text: "I agree strongly")
    disagree_item = find("a", text: "I disagree entirely", visible: :all)

    expect(agree_item[:hidden]).to be_falsey
    expect(disagree_item[:hidden]).to be_truthy

    agree_tab = find('button[data-response-filter-filter-param="agree"]')
    all_tab = find('button[data-response-filter-filter-param="all"]')
    expect(agree_tab["aria-pressed"]).to eq("true")
    expect(all_tab["aria-pressed"]).to eq("false")
  end
end
