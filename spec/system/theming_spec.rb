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

  # Proves the cascade actually WINS at runtime, not just that the value strings
  # exist in the bundle: `@theme inline` emits `var(--agree)` into every utility, and
  # the [data-theme="dark"] block redefines `--agree`, so the resolved custom
  # property on <html> must flip when the toggle does. The hex comes from the CSS var
  # (Spectrum/light #0ea5a4 → dark #2dd4cf), not from the bundle text.
  it "resolves --agree per theme at runtime" do
    visit root_path
    spectrum_light = page.evaluate_script(
      "getComputedStyle(document.documentElement).getPropertyValue('--agree').trim()"
    )
    expect(spectrum_light).to eq("#0ea5a4")

    find('[data-theme-target="toggle"]').click # -> dark
    expect(page).to have_css('html[data-theme="dark"]')
    dark = page.evaluate_script(
      "getComputedStyle(document.documentElement).getPropertyValue('--agree').trim()"
    )
    expect(dark).to eq("#2dd4cf")
  end
end
