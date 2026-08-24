require "rails_helper"

RSpec.describe "Theming", :js do
  # The layout's `stylesheet_link_tag "tailwind"` raises on a clean checkout if the
  # gitignored bundle is missing, which every page-rendering system spec depends on.
  before(:all) { TailwindBuild.once! }

  it "renders the server default data-theme/data-scheme on <html>" do
    visit root_path
    expect(page).to have_css('html[data-theme="light"]')
    expect(page).to have_css('html[data-scheme="spectrum"]')
  end

  it "toggles to dark and persists the choice across a reload" do
    visit root_path
    find('[data-theme-target="toggle"]').click
    expect(page).to have_css('html[data-theme="dark"]')
    visit root_path # reload — the no-FOUC script re-applies from localStorage
    expect(page).to have_css('html[data-theme="dark"]')
  end

  it "cycles the scheme and persists it across a reload" do
    visit root_path
    find('[data-theme-target="scheme"]').click # spectrum -> signal
    expect(page).to have_css('html[data-scheme="signal"]')
    visit root_path
    expect(page).to have_css('html[data-scheme="signal"]')
  end
end
