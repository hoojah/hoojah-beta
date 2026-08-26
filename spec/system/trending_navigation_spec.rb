require "rails_helper"

# Regression: trending links live inside `turbo_frame_tag "trending"`. Without
# `target: "_top"` on the frame, clicking a trending link asks Turbo for a matching
# `trending` frame on the hujah show page — which has none — so Turbo renders
# "Content missing" instead of navigating. Both frame declarations (the feed's lazy
# sidebar src frame and /trending's own frame) now carry `target: "_top"`, so every
# link inside performs a full-page visit.
RSpec.describe "Trending navigation", type: :system, js: true do
  before { Rails.cache.clear }

  it "navigates full-page from a feed-sidebar trending link to the hujah show page" do
    # agree_count seeds the HN-gravity trending score (see Hujah.trending); a fresh
    # record is within the 48h recency window. Matches spec/system/trending_spec.rb.
    hot = create(:hujah, body: "a hot trending take about durian", agree_count: 25)

    login_as_system(create(:user))

    page.current_window.resize_to(1440, 900) # trending sidebar is lg-and-up only
    visit "/"

    # The lazy `trending` frame resolves to the public /trending content.
    within("aside") do
      expect(page).to have_content("a hot trending take about durian")
      click_link "a hot trending take about durian"
    end

    # Full-page visit landed on the hujah show page — not a "Content missing" frame.
    expect(page).to have_current_path(hujah_path(hot.slug))
    expect(page).not_to have_text("Content missing")
    expect(page).to have_content("a hot trending take about durian")
  end

  it "navigates full-page from a /trending rich-page link to the hujah show page" do
    # The standalone /trending page renders `_trending_rich` inside the same
    # `turbo_frame_tag "trending"` (also now `target: "_top"`). Covers the second
    # edited frame declaration (trending/index.html.erb).
    hot = create(:hujah, body: "a hot trending take about durian", agree_count: 25)

    login_as_system(create(:user))

    visit "/trending"

    expect(page).to have_content("a hot trending take about durian")
    click_link "a hot trending take about durian"

    expect(page).to have_current_path(hujah_path(hot.slug))
    expect(page).not_to have_text("Content missing")
    expect(page).to have_content("a hot trending take about durian")
  end
end
