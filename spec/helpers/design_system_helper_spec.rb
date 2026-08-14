require "rails_helper"

# The single source of truth for Hoojah's button idiom (Slice 9, Task 2.1).
#
# Roughly 75 views currently hand-repeat the same raw Tailwind string; eight later
# tasks refactor them onto this helper. That makes the *shape* of the output the
# contract, so these examples assert the properties the design system guarantees
# (`docs/design-system/components/core/Button.prompt.md` + `Button.jsx`) rather than
# the literal string the implementation happens to build. Reordering the classes
# must not turn this file red; dropping the 2px border from `outline` must.
RSpec.describe DesignSystemHelper, type: :helper do
  # Class *tokens*, never a substring match — `include("border")` against a raw
  # string would be satisfied by `border-0`, which means the opposite.
  def classes(**opts)
    helper.ds_button_classes(**opts)
  end

  def tokens(**opts)
    classes(**opts).split
  end

  def borders(**opts)
    tokens(**opts).grep(/\Aborder(-|\z)/)
  end

  def paddings(**opts)
    tokens(**opts).grep(/\Ap[xy]?-/)
  end

  describe "#ds_button_classes" do
    describe "the house style (outline)" do
      it "is a white pill with a 2px border, matching text and fill, and a shadow" do
        expect(tokens).to include(
          "rounded-full", "border-2", "border-primary",
          "text-primary", "fill-primary", "bg-white", "shadow"
        )
      end

      it "is what a bare call renders" do
        expect(classes).to eq(classes(variant: :outline, tone: "primary", size: :md))
      end
    end

    describe "tone" do
      it "recolours the border, text and fill of an outline button" do
        agree = tokens(tone: "agree")

        expect(agree).to include("border-agree", "text-agree", "fill-agree")
        expect(agree).not_to include("border-primary", "text-primary", "fill-primary")
      end

      it "recolours the fill of a solid button" do
        expect(tokens(variant: :solid, tone: "disagree")).to include("bg-disagree")
      end

      # A misspelled tone is the worst defect this helper can produce: silently
      # degrading `"aggree"` renders a perfectly ordinary primary button, so it passes
      # review, passes CI, and ships the wrong colour. Unlike a variant typo it has no
      # visible shape to give it away.
      it "raises on a misspelled tone rather than quietly rendering primary" do
        expect { classes(tone: "aggree") }
          .to raise_error(ArgumentError, /aggree/)
      end

      it "names the permitted tones in the error, so the fix needs no source dive" do
        expect { classes(tone: "aggree") }
          .to raise_error(ArgumentError, /primary, agree, neutral, disagree, grey, light-grey/)
      end

      it "supports the greys, which no stance uses but disabled/secondary chrome does" do
        expect(tokens(tone: "light-grey")).to include("border-light-grey", "text-light-grey")
      end
    end

    describe "variants" do
      it "fills solid buttons with the tone and drops the border entirely" do
        solid = tokens(variant: :solid)

        expect(solid).to include("bg-primary", "text-white", "fill-white", "shadow", "rounded-full")
        expect(borders(variant: :solid)).to be_empty
      end

      it "squares off rect buttons — the auth/signup CTA — and gives them no shadow" do
        rect = tokens(variant: :rect)

        expect(rect).to include("rounded", "bg-primary", "text-white")
        expect(rect).not_to include("rounded-full", "shadow")
      end

      it "inverts on_primary for the blue profile header" do
        on_primary = tokens(variant: :on_primary)

        expect(on_primary).to include("bg-white", "text-primary", "fill-primary", "rounded-full")
        expect(borders(variant: :on_primary)).to be_empty
      end

      it "gives on_primary_outline a hairline white border on transparent" do
        outline = tokens(variant: :on_primary_outline)

        expect(outline).to include("border", "border-white", "text-white", "bg-transparent")
        expect(outline).not_to include("border-2")
      end

      it "locks the on_primary variants to white/primary — they sit on a blue field" do
        expect(classes(variant: :on_primary, tone: "agree")).to eq(classes(variant: :on_primary))
        expect(classes(variant: :on_primary_outline, tone: "agree"))
          .to eq(classes(variant: :on_primary_outline))
      end

      it "strips link buttons back to bare coloured text" do
        link = tokens(variant: :link)

        expect(link).to include("text-primary", "fill-primary", "bg-transparent")
        expect(link).not_to include("shadow")
        expect(borders(variant: :link)).to eq(["border-0"])
        expect(paddings(variant: :link)).to eq(["p-0"])
      end
    end

    describe "size" do
      # `size:` sets type as well as padding — Button.jsx pins a font size per size, so
      # an `md` button dropped into a `text-sm` block must not silently shrink.
      it "defaults to the medium pill at base type" do
        expect(tokens).to include("px-5", "py-2", "text-base")
        expect(tokens).not_to include("text-sm")
      end

      it "tightens padding and type at :sm" do
        expect(tokens(size: :sm)).to include("px-4", "py-1", "text-sm")
        expect(tokens(size: :sm)).not_to include("text-base")
      end

      it "ignores size on the on_primary variants, which are always small" do
        expect(classes(variant: :on_primary, size: :md))
          .to eq(classes(variant: :on_primary, size: :sm))
      end
    end

    # `nil` is not a typo, it is the common case: views pass
    # `variant: local_assigns[:variant]`, and a `local_assigns` miss is nil. All three
    # arguments degrade the same way — an unset local must render the house style, not
    # take the page down.
    it "treats a nil variant, tone or size as the default" do
      expect(classes(variant: nil, tone: nil, size: nil)).to eq(classes)
    end

    # Callers should not have to coerce at the call site. `render "button", variant:
    # "solid"` hands over strings, while an enum or `stance&.to_sym` hands over symbols;
    # all three arguments accept either.
    it "accepts symbols and strings interchangeably" do
      expect(classes(variant: "solid", tone: :agree, size: "sm"))
        .to eq(classes(variant: :solid, tone: "agree", size: :sm))
    end

    it "raises on an unrecognised variant or size too, naming the permitted set" do
      expect { classes(variant: :spaceship) }
        .to raise_error(ArgumentError, /spaceship.*on_primary_outline/m)
      expect { classes(size: :massive) }
        .to raise_error(ArgumentError, /massive.*md, sm/m)
    end

    # The loud failure is for humans and CI. In production a button in the wrong colour
    # is a far smaller problem than a 500 on a page that was otherwise fine, so the same
    # typo degrades there instead of raising.
    it "degrades instead of raising in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      expect(classes(tone: "aggree", variant: :spaceship, size: :massive)).to eq(classes)
    end

    describe "invariants across every variant" do
      # Two halves, and both are needed. Deriving the expectation from BASE stops this
      # example drifting out of sync with the constant, but on its own it would move
      # with any deletion from BASE and stay green — so the tokens the design system
      # actually promises are named too: a centred inline flex row with a gap, no
      # underline when rendered as a link, `active:scale-95` as the ONLY press feedback
      # (no ripple, spinner or fade), and the half-opacity disabled state that has to
      # cancel `cursor-pointer`.
      it "carries the whole shared base on every variant" do
        base = DesignSystemHelper::BASE.split

        expect(base).to include(
          "inline-flex", "items-center", "justify-center", "gap-1",
          "no-underline", "cursor-pointer", "transition", "active:scale-95",
          "disabled:opacity-50", "disabled:cursor-default"
        )

        DesignSystemHelper::VARIANTS.each do |variant|
          expect(tokens(variant: variant)).to include(*base),
            "#{variant} is missing part of the shared button base"
        end
      end

      # `text-sm` / `text-base` are font sizes and `border-0` / `border-2` are widths:
      # they share a prefix with the colour utilities but not the namespace. Subtract
      # them by name rather than allowing their suffixes as colours, or the guard would
      # wave through `bg-sm` and `fill-2` — the very typos it exists to catch.
      it "never emits a colour utility with a blank or unknown token" do
        non_colour = %w[text-sm text-base border-0 border-2]
        known = DesignSystemHelper::TONES + %w[white transparent]

        DesignSystemHelper::VARIANTS.product(DesignSystemHelper::TONES).each do |variant, tone|
          colours = tokens(variant: variant, tone: tone).grep(/\A(bg|text|border|fill)-/) - non_colour

          colours.each do |token|
            value = token.split("-", 2).last
            expect(known).to include(value),
              "#{variant}/#{tone} emitted `#{token}`, whose colour is not a design token"
          end
        end
      end
    end

    it "keeps the variant lookup off the public view API" do
      # `private` in a mixed-in helper module is a boundary against
      # `helper.ds_button_variant` / `ActionController::Base.helpers.…`, and a signal
      # to views that this is not part of the interface.
      expect(helper).not_to respond_to(:ds_button_variant)
      expect(helper.respond_to?(:ds_button_variant, true)).to be(true)
    end
  end
end

# `ds_button_classes` interpolates the tone into `bg-` / `text-` / `border-` / `fill-`,
# so Tailwind's source scanner never sees those class names as literals and will not
# emit them. `@source inline(...)` in app/assets/tailwind/application.css is what puts
# them in the bundle. Nothing else proves that line is still correct — and since Task
# 1.1 excluded `docs/` from the scanner, prose in the design-system mirror no longer
# masks a missing entry. Derive the expectation from the helper itself so adding a
# tone without safelisting it fails here rather than in a silently unstyled view.
RSpec.describe "Button tone utilities reach the compiled bundle" do
  # The bundle is gitignored and nothing in the boot path rebuilds it.
  before(:all) { TailwindBuild.once! }

  let(:bundle) { Rails.root.join("app/assets/builds/tailwind.css").read }

  def emitted?(klass)
    # `active:scale-95` is escaped as `.active\:scale-95` in the output. The trailing
    # lookahead is the boundary: without it `.rounded` would match `.rounded-full`.
    bundle.match?(/\.#{Regexp.escape(klass.gsub(":", '\\:'))}(?![\w-])/)
  end

  # Not `ActionController::Base.helpers` — that proxy carries only Action View's own
  # modules, so it would raise NoMethodError here. Going through ApplicationController
  # also confirms the helper is genuinely mixed into every app view.
  let(:view) { ApplicationController.helpers }

  it "generates every utility the helper can produce, for every variant and tone" do
    wanted = DesignSystemHelper::VARIANTS.product(DesignSystemHelper::TONES).flat_map { |variant, tone|
      %i[md sm].flat_map { |size| view.ds_button_classes(variant: variant, tone: tone, size: size).split }
    }.uniq

    missing = wanted.reject { |klass| emitted?(klass) }

    expect(missing).to be_empty,
      "these button utilities are absent from app/assets/builds/tailwind.css — " \
      "add them to the `@source inline(...)` safelist: #{missing.join(", ")}"
  end
end
