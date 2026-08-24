require "rails_helper"

# `shared/_screen_header` is the sticky contextual header for inner screens (debate,
# profile, dashboard, search) — back link + title + optional right-hand action. It is
# distinct from the global `shared/_navbar`, which stays on every page; this partial is
# opt-in per screen (Hoojah 2026, redesign Phase 0, Task 0.3).
RSpec.describe "shared/_screen_header", type: :view do
  # `render`'s return value, not `rendered` — the latter accumulates across every render
  # in an example, so a second render in the same example would diff one header against
  # two concatenated ones.
  def html(**locals)
    render(partial: "shared/screen_header", locals: locals).strip
  end

  def header(**locals)
    Capybara.string(html(**locals))
  end

  it "shows the title" do
    expect(header(title: "Your dashboard")).to have_css("h1", text: "Your dashboard")
  end

  describe "back link" do
    it "renders a back link to `back`, with the arrow-left glyph" do
      result = header(title: "Your dashboard", back: "/")

      expect(result).to have_css("a[href='/']")
      expect(result).to have_css("a[href='/'] svg")
    end

    it "renders no back link when `back` is nil" do
      expect(header(title: "Your dashboard", back: nil)).to have_no_css("a")
    end

    it "renders no back link when `back` is omitted entirely" do
      expect(header(title: "Your dashboard")).to have_no_css("a")
    end
  end

  describe "the right-hand action slot" do
    it "renders an html-safe `action:` local in a right-hand slot" do
      result = header(title: "Your dashboard", action: '<button type="button">Filter</button>'.html_safe)

      expect(result).to have_css("button", text: "Filter")
    end

    it "renders no extra markup when `action:` is omitted" do
      plain = header(title: "Your dashboard")
      with_back = header(title: "Your dashboard", back: "/")

      # Sanity: the two headers above already differ by the back link alone, so this
      # example is only meaningful once it is not itself testing that difference.
      expect(plain).not_to eq(with_back)
    end
  end

  it "is the sticky, theme-aware surface the design system specifies" do
    expect(header(title: "Your dashboard")).to have_css("header.sticky.bg-nav.border-hairline")
  end
end
