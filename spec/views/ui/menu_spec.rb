require "rails_helper"

# `ui/_menu` is the dropdown panel three surfaces share verbatim — the navbar avatar
# menu, `hujahs/_share_menu`, and the more-actions menu in `hujahs/show`
# (docs/design-system/components/navigation/DropdownMenu.prompt.md).
#
# Like `ui/_card` it is a LAYOUT partial, and like `ui/_card` most of what it guarantees
# is a class string. The examples below assert the properties the design system names,
# not the literal string the implementation builds: reordering the classes must not turn
# this file red; dropping the shadow, or rounding the corners away, must.
RSpec.describe "ui/_menu", type: :view do
  # `render`'s return value, not `rendered` — the latter accumulates across every render
  # in an example, so the comparison examples below would diff one panel against two.
  def html(width: "w-56", **locals, &block)
    block ||= proc { "contents" }
    render(layout: "ui/menu", locals: locals.merge(width: width), &block).strip
  end

  def menu(**locals, &block)
    Capybara.string(html(**locals, &block))
  end

  def tokens(**locals)
    menu(**locals).find("div")[:class].split
  end

  it "renders the block it wraps" do
    expect(menu { "Log Out" }).to have_css("div", text: "Log Out")
  end

  it "is the white shadowed surface the design system specifies" do
    expect(tokens).to include("bg-card", "shadow")
  end

  # The one place this partial parts company with `ui/_card`, whose first rule is
  # "never round a feed card". DropdownMenu.prompt.md specifies a 4px-rounded floating
  # panel, so `rounded` here is the design system, not drift — and a future agent
  # applying the card rule to a menu would be making it wrong.
  it "IS rounded, unlike a card" do
    expect(tokens).to include("rounded")
    expect(tokens).not_to include("rounded-full", "rounded-lg")
  end

  # `absolute` only means anything against a positioned ancestor, and all three call
  # sites supply `<details class="relative">`. Pinned because the failure is a panel
  # that renders in the document flow and shoves the page around, not an error.
  it "floats from the right edge of its trigger" do
    expect(tokens).to include("absolute", "right-0", "z-10")
  end

  describe "width" do
    it "takes the caller's width" do
      expect(tokens(width: "w-52")).to include("w-52")
    end

    # The whole reason `width:` is a required local rather than a default overridable
    # through `class:`. Same-family utilities resolve by their order in the compiled
    # bundle, not by call order, so a baked-in default would beat the caller silently.
    # Nothing in the class string may pre-empt the caller's choice.
    it "carries no width of its own that a caller would have to fight" do
      widths = tokens(width: "w-52").grep(/\Aw-/)

      expect(widths).to eq(["w-52"])
    end

    it "raises at the call site rather than rendering a menu of no particular width" do
      expect { render(layout: "ui/menu", locals: {}) { "x" } }
        .to raise_error(ActionView::Template::Error, /width/)
    end
  end

  describe "padding" do
    before(:all) { TailwindBuild.once! }

    # The opposite of the width case, and the reason `p-2` can safely be baked in:
    # Tailwind emits the shorthand ahead of the longhands, so a caller's `px-3` really
    # does win on the x axis. The bundle offsets are asserted, not assumed, so that if
    # the emission order ever flips this says so instead of a menu quietly ignoring its
    # call site — the failure the header comment promises cannot happen.
    it "is padded, and a caller's longhand can still override it" do
      expect(tokens).to include("p-2")
      expect(tokens(class: "px-3")).to include("p-2", "px-3")
      expect(TailwindBuild.bundle.index(".p-2")).to be < TailwindBuild.bundle.index(".px-3")
    end
  end

  it "appends caller classes, since the panels differ in more than width" do
    expect(tokens(class: "mt-2")).to include("mt-2")
  end

  # It is the panel, not the disclosure. The `<details>`/`<summary>` stay at the call
  # site because `_share_menu`'s carries a frozen `data-controller` and three
  # `data-*-value` attributes, and because the three triggers have nothing in common.
  it "owns no trigger — no <details>, no <summary>" do
    expect(menu).to have_no_css("details")
    expect(menu).to have_no_css("summary")
  end
end
