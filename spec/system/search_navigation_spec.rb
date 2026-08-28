require "rails_helper"

# Regression: search results live inside `<turbo-frame id="search-results">`
# (search/index.html.erb). Without `target: "_top"` on the frame, clicking any
# result — a hoojah row (→ /hoojah/:slug), a person row (→ /u/:username), or a
# hashtag chip/row (→ /t/:name) — asks Turbo for a matching `search-results`
# frame on the destination page, which has none, so Turbo renders "Content
# missing" instead of navigating. The frame now carries `target="_top"`, so
# result links perform full-page visits — while the search form keeps its
# explicit `data: {turbo_frame: "search-results"}`, which overrides the frame
# default and keeps live-suggest swapping only the frame (guarded by
# spec/system/search_spec.rb's query-string-sensitive current_path check). Same
# bug/fix pattern as spec/system/trending_navigation_spec.rb.
RSpec.describe "Search navigation", type: :system, js: true do
  it "navigates full-page from a hoojah top-match to the hoojah show page" do
    hujah = create(:hujah, body: "a searchable claim about teh tarik pricing")

    login_as_system(create(:user))
    visit "/search"
    fill_in "Search", with: "teh tarik pricing"

    within "turbo-frame#search-results" do
      find("a[href='#{hujah_path(hujah.slug)}']").click
    end

    expect(page).to have_current_path(hujah_path(hujah.slug))
    expect(page).not_to have_text("Content missing")
    expect(page).to have_content("teh tarik pricing")
  end

  it "navigates full-page from a browse hashtag chip to the tag feed" do
    tag = create(:hashtag, display: "ketupat")

    login_as_system(create(:user))
    visit "/search"

    within "turbo-frame#search-results" do
      click_link "#ketupat", match: :first
    end

    expect(page).to have_current_path(tag_path(tag.name))
    expect(page).not_to have_text("Content missing")
  end
end
