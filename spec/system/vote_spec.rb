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
    expect(page).to have_content("100%")
    expect(hujah.reload.agree_count).to eq(1)
  end
end
