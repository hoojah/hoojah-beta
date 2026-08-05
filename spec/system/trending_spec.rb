require "rails_helper"

# Cuprite coverage: on a wide (lg) viewport the feed renders the lazily-loaded
# trending sidebar frame, which resolves to the public /trending content.
RSpec.describe "Trending sidebar", type: :system, js: true do
  before { Rails.cache.clear }

  it "shows the trending sidebar frame on a wide viewport" do
    create(:hujah, body: "a hot trending take", agree_count: 25)

    page.current_window.resize_to(1440, 900)
    visit "/"

    within("aside") do
      expect(page).to have_content(/trending/i) # CSS uppercases the heading text
      expect(page).to have_content("a hot trending take")
    end
  end
end
