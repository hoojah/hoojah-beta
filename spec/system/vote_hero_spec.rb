require "rails_helper"

RSpec.describe "Vote hero", type: :system, js: true do
  it "taps to cast a normal vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)

    find('[data-stance="agree"]').click # tap
    # Secret ballot (2a/A7): a single vote is sub-k, so the hero shows the total-only
    # label ("1 vote"), not a per-stance percentage. Its appearance (replacing the
    # initial "No votes yet") proves the in-place turbo re-render just as "100%" did.
    expect(page).to have_content("1 vote")
    expect(h.reload.agree_count).to eq 1
    expect(h.conviction_count).to eq 0
  end

  it "holds to cast a conviction vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)

    hold('[data-stance="disagree"]', 1.3)
    # Secret ballot (2a/A7): sub-k, so the total-only label shows instead of "100%".
    expect(page).to have_content("1 vote")
    expect(h.reload.disagree_count).to eq 1
    expect(h.conviction_count).to eq 1
    expect(h.votes.last.conviction).to be true
  end
end
