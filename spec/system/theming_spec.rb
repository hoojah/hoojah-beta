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
end
