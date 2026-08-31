require "rails_helper"

RSpec.describe "Child card reply count", type: :system, js: true do
  it "shows a reply count on a response that has its own visible reply, and none on a response without" do
    author = create(:user)
    parent = create(:hujah, user: author)

    with_reply = create(:hujah, user: author, parent: parent, vote: 1, body: "A response that has its own thread")
    create(:hujah, user: create(:user), parent: with_reply, body: "A grandchild reply under the response")

    create(:hujah, user: author, parent: parent, vote: 3, body: "A response with no further replies")

    visit hujah_path(parent.slug)

    within find("[data-response-filter-target='item']", text: "A response that has its own thread") do
      expect(page).to have_css("[data-testid='reply-count']", text: "1 reply")
    end

    # Scope the negative to the reply-count badge element itself, not a substring of the
    # card body: `not_to have_content("reply")` would false-fail the day a copy edit put
    # the word "reply" in an unrelated response body.
    within find("[data-response-filter-target='item']", text: "A response with no further replies") do
      expect(page).to have_no_css("[data-testid='reply-count']")
    end
  end
end
