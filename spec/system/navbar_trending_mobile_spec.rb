require "rails_helper"

# The mobile/tablet Trending nav button is `lg:hidden` (present below 1024px). Its
# label span is `hidden md:inline` (app/views/shared/_navbar.html.erb) — icon-only
# below md (768px), icon+label in the md–lg tablet band. So: hidden on a phone,
# shown on a tablet-width viewport that is still under lg.
RSpec.describe "Navbar trending label on mobile", type: :system, js: true do
  it "hides the Trending label on a small phone and shows it on a tablet" do
    login_as_system(create(:user))

    page.current_window.resize_to(360, 780)
    visit "/"
    label = find("a[aria-label='Trending'] span", text: "Trending", visible: :all)
    expect(label).not_to be_visible

    # 820px: at/above md (768) so the label shows, still below lg (1024) so the
    # button itself is present.
    page.current_window.resize_to(820, 900)
    visit "/"
    expect(find("a[aria-label='Trending'] span", text: "Trending")).to be_visible
  end
end
