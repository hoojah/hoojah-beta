require "rails_helper"

RSpec.describe "Vote hero", type: :system, js: true do
  it "taps to cast a normal vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)

    find('[data-stance="agree"]').click # tap
    expect(page).to have_content("100%")
    expect(h.reload.agree_count).to eq 1
    expect(h.conviction_count).to eq 0
  end

  it "holds to cast a conviction vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)

    hold('[data-stance="disagree"]', 1.3)
    expect(page).to have_content("100%")
    expect(h.reload.disagree_count).to eq 1
    expect(h.conviction_count).to eq 1
    expect(h.votes.last.conviction).to be true
  end
end
