require "rails_helper"

# Cuprite (headless Chrome) coverage for the owner-only analytics dashboard
# (Slice 5, Part B). Reuses the Slice-3 `login_as_system` harness (spec/support/devise.rb
# re-authenticates the user on every request). All synchronisation is Capybara
# `have_*` auto-waits — no sleeps. The page is 2-3 grouped queries rendered in one
# pass (no Turbo frames), so a single `visit` is enough.
RSpec.describe "Analytics dashboard", type: :system, js: true do
  let(:user) { create(:user) }

  it "shows totals, a distribution split, and suppresses a low-vote hoojah" do
    create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1,
      body: "A well-voted hoojah")
    create(:hujah, user: user, agree_count: 1, neutral_count: 0, disagree_count: 0,
      body: "A quiet hoojah")

    login_as_system(user)
    visit dashboard_path

    expect(page).to have_content("Your dashboard")
    # Totals: 5 votes received, 0 arguments received.
    expect(page).to have_content("Total votes received")
    expect(page).to have_content("5")
    expect(page).to have_content("Followers")
    # The well-voted hoojah shows its split; agree is 3/5 = 60%.
    expect(page).to have_content("A well-voted hoojah")
    expect(page).to have_content("60%")
    # The quiet hoojah (1 vote) is suppressed.
    expect(page).to have_content("A quiet hoojah")
    expect(page).to have_content("fewer than 5 votes")
  end
end
