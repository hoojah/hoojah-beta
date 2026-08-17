require "rails_helper"

# Slice 9 / Task 1.2. The navbar brand is the gradient wordmark asset, not the
# bold indigo "Hoojah" text it replaced.
#
# The second example guards the defect documented in docs/design-system/MIRROR-NOTES.md:
# the design-system copy of logo.svg carries `class="st0"`..`class="st6"` but ships
# neither a <style> block nor any fill, so its seven radialGradient defs go
# unreferenced and the wordmark renders solid black. If someone ever re-vendors
# that broken copy over ours, this fails instead of silently shipping a black logo.
RSpec.describe "Branding", type: :system do
  let(:logo) { Rails.root.join("app/assets/images/logo.svg") }

  it "renders the wordmark asset as the navbar brand, linked to the root" do
    visit "/"

    brand = find("nav a[href='#{root_path}'] img[alt='Hoojah']")

    expect(brand[:src]).to match(%r{/logo\b.*\.svg}i)
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
