require "rails_helper"

# Discover / search screen (Hoojah 2026, Phase 2.4). Two coverage modes on purpose:
# a Cuprite (`js: true`) example for the debounced live-suggest
# (search_controller.js), and a plain rack_test example (the system-spec default —
# see spec/support/capybara.rb) for the JS-off path, since rack_test has no
# JavaScript at all. Same route, same `search/_results` partial either way — the
# constraint this file exists to prove.
RSpec.describe "Search", type: :system do
  it "debounces typing and updates the results frame in place, without leaving the page", js: true do
    create(:hujah, body: "a very unique debounce marker phrase right here")

    visit "/search"
    fill_in "Search", with: "debounce marker"

    expect(page).to have_content("debounce marker phrase right here")
    expect(page).to have_current_path("/search")
  end

  it "returns the same results via a plain native form submit with JS off" do
    create(:hujah, body: "a jsoff findable claim right here")

    visit "/search"
    fill_in "Search", with: "jsoff findable"
    click_button "Search"

    expect(page).to have_content("jsoff findable claim right here")
  end
end
