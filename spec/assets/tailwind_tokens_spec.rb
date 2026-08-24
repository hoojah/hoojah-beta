require "rails_helper"

# Guards the Hoojah 2026 runtime token bridge (Track 1, Task 1.1): the @theme
# stance/surface colours must indirect through runtime custom properties so the
# compiled utilities (bg-agree, text-ink, …) retint per data-theme/data-scheme
# on <html>, and the Spectrum/dark/scheme value blocks must reach the bundle.
#
# `TailwindBuild` (spec/support/tailwind_build.rb) builds once per suite and
# exposes the compiled CSS via `.bundle`. The bundle is MINIFIED (no space after
# a declaration colon), so assertions tolerate optional whitespace via regex or
# match the minified spelling exactly.
RSpec.describe "Tailwind 2026 tokens" do
  before(:all) { TailwindBuild.once! }

  let(:css) { TailwindBuild.bundle }

  it "chains stance utilities onto runtime --agree/--neutral/--disagree vars" do
    expect(css).to match(/--color-agree:\s*var\(--agree\)/)
    expect(css).to match(/--color-neutral:\s*var\(--neutral\)/)
    expect(css).to match(/--color-disagree:\s*var\(--disagree\)/)
  end

  # Tailwind's minifier strips the quotes from attribute selectors
  # (`[data-theme="dark"]` → `[data-theme=dark]`), which is functionally
  # identical CSS — the assertions below allow the optional quotes.
  it "defines Spectrum defaults on :root and a dark override" do
    expect(css).to match(/:root\s*\{[^}]*--agree:\s*#0ea5a4/m)
    expect(css).to match(/\[data-theme="?dark"?\][^{]*\{[^}]*--agree:\s*#2dd4cf/m)
  end

  it "defines Signal and Ballot scheme overrides" do
    expect(css).to match(/\[data-scheme="?signal"?\]/)
    expect(css).to match(/\[data-scheme="?ballot"?\]/)
  end
end
