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

  # `@theme inline` emits the runtime var DIRECTLY into each utility rule
  # (`.bg-agree{background-color:var(--agree)}`) rather than declaring a
  # `--color-agree: var(--agree)` indirection on :root — that is what makes the
  # utility re-resolve per element, so the cascade retints wherever data-theme /
  # data-scheme sits below <html> rather than only on :root. Assert the emitted
  # rules, not the (now-absent) --color-* declaration.
  it "chains stance utilities onto runtime --agree/--neutral/--disagree vars" do
    expect(css).to match(/\.bg-agree\s*\{\s*background-color:\s*var\(--agree\)\s*\}/)
    expect(css).to match(/\.text-neutral\s*\{\s*color:\s*var\(--neutral\)\s*\}/)
    expect(css).to match(/\.border-disagree\s*\{\s*border-color:\s*var\(--disagree\)\s*\}/)
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
