require "rails_helper"

RSpec.describe "Smoke", type: :system, js: true do
  it "loads the feed" do
    create(:hujah, user: create(:user))
    visit "/"
    expect(page).to have_css('[data-testid="hujah-card"]')
  end
end
