require "rails_helper"

RSpec.describe "Voting", type: :system, js: true do
  it "updates the vote hero in place without a full reload" do
    voter = create(:user)
    hujah = create(:hujah, user: create(:user))
    login_as_system(voter)
    visit "/hoojah/#{hujah.slug}"
    within "##{ActionView::RecordIdentifier.dom_id(hujah, :vote_hero)}" do
      find('[data-stance="agree"]').click
    end
    # Secret ballot (2a/A7): a single vote is sub-k, so the hero renders the total-only
    # label ("1 vote") rather than a per-stance percentage. Its appearance (replacing the
    # initial "No votes yet") proves the widget re-rendered in place without a reload.
    expect(page).to have_content("1 vote")
    expect(hujah.reload.agree_count).to eq(1)
  end
end
