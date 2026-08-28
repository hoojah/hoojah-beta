require "rails_helper"

# The mobile Trending nav button (lg:hidden) shows an icon + label. On small
# phones the label is hidden (icon-only); it returns at >=420px.
RSpec.describe "Navbar trending label on mobile", type: :system, js: true do
  it "hides the Trending label on a small phone and shows it on a large one" do
    login_as_system(create(:user))

    page.current_window.resize_to(360, 780)
    visit "/"
    label = find("a[aria-label='Trending'] span", text: "Trending", visible: :all)
    expect(label).not_to be_visible

    page.current_window.resize_to(500, 900)
    visit "/"
    expect(find("a[aria-label='Trending'] span", text: "Trending")).to be_visible
  end
end
