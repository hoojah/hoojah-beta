require "rails_helper"

# Slice 9 / Task 1.2. The navbar brand is the gradient wordmark asset, not the
# bold indigo "Hoojah" text it replaced. As of the 2026 navbar restructure the brand
# link carries TWO glyphs — the full `logo.svg` wordmark (shown at >=sm) and the compact
# `logo-mark.svg` "h" mark (shown below sm) — one visible per breakpoint via CSS. Both
# are decorative (empty alt); the link's own aria-label carries the accessible name, so
# the brand is found here by asset src rather than by alt.
#
# The second example guards the defect documented in docs/design-system/MIRROR-NOTES.md:
# the design-system copy of logo.svg carries `class="st0"`..`class="st6"` but ships
# neither a <style> block nor any fill, so its seven radialGradient defs go
# unreferenced and the wordmark renders solid black. If someone ever re-vendors
# that broken copy over ours, this fails instead of silently shipping a black logo.
RSpec.describe "Branding", type: :system do
  let(:logo) { Rails.root.join("app/assets/images/logo.svg") }

  it "renders both brand glyphs in the navbar, linked to the root" do
    visit "/"

    # The brand link is the only root link in the navbar carrying an <img>; qualify by
    # the image so a second `a[href="/"]` on the page can't make the match ambiguous.
    wordmark = find("nav a[href='#{root_path}'] img[src*='logo']:not([src*='mark'])", visible: :all)
    expect(wordmark[:src]).to match(%r{/logo\b.*\.svg}i)

    # Compact "h" mark — the below-sm brand, in the same link.
    expect(page).to have_css("nav a[href='#{root_path}'] img[src*='logo-mark']", visible: :all)
  end

  it "references every gradient it defines, so the wordmark is not solid black" do
    svg = logo.read

    defined_gradients = svg.scan(/<radialGradient\s+id="([^"]+)"/).flatten
    referenced = svg.scan(/url\(#([^)]+)\)/).flatten.uniq

    expect(defined_gradients).not_to be_empty
    expect(defined_gradients - referenced).to be_empty,
      "unreferenced gradients would render as solid black: #{(defined_gradients - referenced).join(", ")}"
  end
end
