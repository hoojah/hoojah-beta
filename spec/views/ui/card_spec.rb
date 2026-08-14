require "rails_helper"

# `ui/_card` is the white surface every piece of Hoojah content sits on (Slice 9,
# Task 2.3). Card.prompt.md opens with "Never round a feed card", and the compact
# child/profile/notification rows carry an 8px colour-coded left border that the
# design system calls "a real motif of this brand" — so the two load-bearing
# examples here are the ABSENCE of a rounding class and the presence of that border.
#
# It is a LAYOUT partial: it wraps a block. Every example goes through `render
# layout:`, because that is the only call form that passes the block through — see
# the "as a layout partial" group.
RSpec.describe "ui/_card", type: :view do
  # `render`'s return value, not `rendered`: the latter accumulates across every
  # render in one example, so the comparison examples below would each be diffing
  # one card against two concatenated ones.
  def html(body = "contents", **locals)
    render(layout: "ui/card", locals: locals) { body }.strip
  end

  def card(body = "contents", **locals)
    Capybara.string(html(body, **locals))
  end

  describe "the surface" do
    it "is a white shadowed box" do
      expect(card).to have_css("div.shadow.bg-white")
    end

    # Card.prompt.md: "Never round a feed card." A stray `rounded` here would round
    # every card in the app at once, which is exactly why it is asserted centrally.
    it "is square-cornered — no rounding class, at any size or stance" do
      %w[rounded rounded-sm rounded-md rounded-lg rounded-full].each do |klass|
        expect(card(stance: "agree", padded: true)).to have_no_css("div.#{klass}")
      end
    end

    it "renders a plain div by default" do
      expect(card).to have_css("div")
    end

    it "carries no padding of its own unless asked — most cards lay out their own rows" do
      expect(card).to have_no_css("div.px-4")
    end

    it "pads on request" do
      expect(card(padded: true)).to have_css("div.px-4.py-3")
    end
  end

  describe "stance" do
    it "adds the 8px coloured left border" do
      expect(card(stance: "agree")).to have_css("div.border-l-8.border-agree")
    end

    it "leaves an unstanced card with no left border at all" do
      expect(card).to have_no_css("div.border-l-8")
    end

    # `border-l-8` is a width and `border-agree` a colour: both are needed, and a
    # card that lost the width would silently drop the motif while keeping a class
    # that still looks right in the markup.
    it "colours every stance the product actually renders" do
      DesignSystemHelper::CARD_STANCES.each do |stance|
        expect(card(stance: stance)).to have_css("div.border-l-8.border-#{stance}")
      end
    end

    it "treats a nil stance as unset rather than as a colour" do
      expect(html(stance: nil)).to eq(html)
    end

    it "accepts a symbol as readily as a string" do
      expect(html(stance: :agree)).to eq(html(stance: "agree"))
    end

    # The dangerous typo: `border-aggree` is a class with no rule behind it, so the
    # card renders with no border and looks merely unstanced. Neither review nor CI
    # would catch it. Action View wraps whatever a template raises.
    it "raises on a misspelled stance rather than emitting a class with no rule" do
      expect { card(stance: "aggree") }
        .to raise_error(ActionView::Template::Error, /aggree.*agree, neutral, disagree/m)
    end
  end

  describe "the element" do
    it "becomes whatever `as:` names, so a feed row can be an <article>" do
      expect(card(as: "article")).to have_css("article.shadow.bg-white")
      expect(card(as: "article")).to have_no_css("div")
    end

    it "passes `id:` through, for the dom_id every Turbo Stream targets" do
      expect(card(id: "hujah_7")).to have_css("div#hujah_7")
    end

    it "emits no id attribute when none is given" do
      expect(card).to have_no_css("div[id]")
    end

    it "appends caller classes, for the margins that vary by call site" do
      expect(card(class: "mb-2")).to have_css("div.shadow.bg-white.mb-2")
    end
  end

  describe "as a layout partial" do
    it "renders the block it wraps" do
      expect(card("Hello Malaysia")).to have_text("Hello Malaysia")
    end

    it "nests the block inside the card element, not beside it" do
      expect(card("Hello Malaysia")).to have_css("div.bg-white", text: "Hello Malaysia")
    end

    # Executable documentation of the call form for the eight Phase 4 refactors, and
    # of the one that does not work.
    #
    # `RenderingHelper#render` branches on its first argument. Given a Hash AND a
    # block it renders `options[:layout]` as the partial and ignores `options[:partial]`
    # entirely — so `render partial: "ui/card" do … end` looks up `nil`. It fails
    # LOUDLY, which is the good news: a Phase 4 refactor cannot ship a silently empty
    # card this way. Pin it, because the message names neither `render` nor the card.
    it "raises rather than rendering when called with `partial:` instead of `layout:`" do
      expect { render(partial: "ui/card", locals: {}) { "Hello Malaysia" } }
        .to raise_error(ArgumentError, /to_partial_path/)
    end

    # The String form takes the block too — it is the `else` branch, which forwards
    # the block straight to `render_partial`. Worth pinning only because it is the
    # form a refactor is most likely to reach for by muscle memory, and "does it drop
    # the block?" is not answerable by reading the call site.
    it "also wraps the block in the bare string form" do
      expect(render("ui/card") { "Hello Malaysia" }).to include("Hello Malaysia")
    end
  end
end
