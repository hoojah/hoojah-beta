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

  # The initials the avatar falls back to when a user has no photo. Rendering is
  # `spec/views/ui/avatar_spec.rb`'s job; this is the string function on its own,
  # because the interesting cases are the degenerate names, not the happy path.
  describe "#ds_initials" do
    it "takes the first letter of the first two words" do
      expect(helper.ds_initials("Maya Zaharudin")).to eq("MZ")
    end

    it "gives a one-word name a single letter rather than padding it" do
      expect(helper.ds_initials("Maya")).to eq("M")
    end

    # Malaysian names routinely run to four or five words ("Nurul Izzah binti
    # Anwar"), and three letters do not fit a 32px circle.
    it "stops at two letters however many words the name has" do
      expect(helper.ds_initials("Nurul Izzah binti Anwar Ibrahim")).to eq("NI")
    end

    it "upcases, so a lowercased handle-style name still reads as initials" do
      expect(helper.ds_initials("maya zaharudin")).to eq("MZ")
    end

    # `full_name` is validated present, but a name of pure whitespace passes that
    # validation, and a nil arrives from any caller that reaches through an
    # association. Both must produce a glyph — an empty circle looks broken.
    it "renders ? for a blank, whitespace-only or nil name" do
      expect(helper.ds_initials("")).to eq("?")
      expect(helper.ds_initials("   ")).to eq("?")
      expect(helper.ds_initials(nil)).to eq("?")
    end

    it "ignores the extra whitespace a copy-pasted name carries" do
      expect(helper.ds_initials("  Maya   Zaharudin  ")).to eq("MZ")
    end

    it "keeps a non-ASCII initial intact rather than dropping the letter" do
      expect(helper.ds_initials("Åsa Ibrahim")).to eq("ÅI")
    end
  end

  describe "#ds_avatar_classes" do
    # Avatar.jsx sizes the fallback type as `Math.round(size * 0.38)`, so a size
    # entry without a font size would render 96px and 32px initials identically.
    it "pairs a box with a type size for every permitted size" do
      DesignSystemHelper::AVATAR_SIZES.each do |size, classes|
        tokens = helper.ds_avatar_classes(size: size).split

        expect(tokens).to eq(classes.split)
        expect(tokens.grep(/\Aw-/).size).to eq(1), "#{size} has no single width"
        expect(tokens.grep(/\Ah-/).size).to eq(1), "#{size} has no single height"
        expect(tokens.grep(/\Atext-/).size).to eq(1), "#{size} has no font size"
      end
    end

    it "renders square circles — width and height always agree" do
      DesignSystemHelper::AVATAR_SIZES.each_key do |size|
        w, h = helper.ds_avatar_classes(size: size).split.grep(/\A[wh]-/).map { |t| t.split("-").last }

        expect(w).to eq(h), "#{size} is an ellipse: w-#{w} h-#{h}"
      end
    end

    # Same convention as `ds_button_classes`: an unpassed local is nil and must take
    # the default, a typo must be loud. The permitted list is derived from the constant
    # rather than restated, so reordering `AVATAR_SIZES` cannot fail this on a diff.
    let(:permitted) { Regexp.escape(DesignSystemHelper::AVATAR_SIZES.keys.join(", ")) }

    it "treats a nil size as unset, and a misspelled one as a typo" do
      expect(helper.ds_avatar_classes(size: nil)).to eq(helper.ds_avatar_classes)
      expect { helper.ds_avatar_classes(size: :massive) }
        .to raise_error(ArgumentError, /massive.*#{permitted}/m)
    end

    # Avatar.prompt.md documents these sizes as pixel numbers — 96 profile header, 44
    # hujah card, 40 follower row — so `size: 44` is the likeliest wrong guess anyone
    # reading the design contract will make. `Integer#to_sym` does not exist, so without
    # coercion it lands as a NoMethodError deep in the helper instead of the one message
    # that would tell them what to write.
    it "answers a pixel number with the same friendly error, not NoMethodError" do
      expect { helper.ds_avatar_classes(size: 44) }
        .to raise_error(ArgumentError, /44.*#{permitted}/m)
    end
  end

  # `ui/_card`'s class string. Rendering is spec/views/ui/card_spec.rb's job; what is
  # here is the part that has no markup to show for it — the closed stance set, and
  # the production behaviour a view spec cannot reach.
  describe "#ds_card_classes" do
    def tokens(**opts)
      helper.ds_card_classes(**opts).split
    end

    it "is a white shadowed box and nothing else by default" do
      expect(tokens).to eq(%w[shadow bg-white])
    end

    # Card.prompt.md's first line. Asserted on the token list rather than by naming
    # the rounding classes, so a `rounded-xl` nobody thought of still fails.
    it "never rounds a card, at any stance" do
      DesignSystemHelper::CARD_STANCES.each do |stance|
        expect(tokens(stance: stance, padded: true).grep(/\Arounded/)).to be_empty
      end
    end

    it "pairs the 8px width with the stance colour — either alone paints nothing" do
      expect(tokens(stance: "agree")).to include("border-l-8", "border-agree")
    end

    it "adds padding only when asked" do
      expect(tokens.grep(/\Ap[xy]?-/)).to be_empty
      expect(tokens(padded: true)).to include("px-4", "py-3")
    end

    # Same convention as the two helpers above: an unpassed local is nil and means
    # "no left border"; a typo is loud and names the set.
    it "treats a nil stance as unset, and a misspelled one as a typo" do
      expect(helper.ds_card_classes(stance: nil)).to eq(helper.ds_card_classes)
      expect { helper.ds_card_classes(stance: "aggree") }
        .to raise_error(ArgumentError, /aggree.*#{Regexp.escape(DesignSystemHelper::CARD_STANCES.join(", "))}/m)
    end

    it "accepts a symbol as readily as a string" do
      expect(helper.ds_card_classes(stance: :agree)).to eq(helper.ds_card_classes(stance: "agree"))
    end

    # A card with no left border beats a 500 on a feed that was otherwise fine — the
    # same trade `ds_button_classes` makes, and the reason `ds_option` takes an env.
    it "degrades to an unstanced card instead of raising in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      expect(helper.ds_card_classes(stance: "aggree")).to eq(helper.ds_card_classes)
    end
  end

  # DebateCard.prompt.md calls this mapping FIXED, and DebateCard.jsx exports it as
  # `DEBATE_STATE_COLOR` because two components read it — the row in a hoojah's Debates
  # lens and the label on the transcript screen.
  #
  # Until Slice 9 Task 4.5's review those two Rails partials each held their own inline
  # copy of the hash and NOTHING asserted either. That is the dangerous shape: editing
  # one and not the other leaves both rendering a real Tailwind class, keeps the suite
  # green, and makes the same debate read as two different states depending on the
  # screen. These examples name all four pairs literally, so a one-sided edit is red.
  describe "#ds_debate_state_color" do
    it "maps each of the four debate states to its fixed tone" do
      expect(helper.ds_debate_state_color("pending")).to eq("agree")
      expect(helper.ds_debate_state_color("active")).to eq("primary")
      expect(helper.ds_debate_state_color("concluded")).to eq("grey")
      expect(helper.ds_debate_state_color("declined")).to eq("light-grey")
    end

    it "covers every status the model can actually be in" do
      expect(DesignSystemHelper::DEBATE_STATE_COLOR.keys).to match_array(Debate.statuses.keys)
    end

    # `status` reaches this helper from an enum column, not from a view author's
    # keyboard, so an unknown value is a schema change rather than a typo — and it
    # degrades to grey in EVERY environment, unlike the `ds_option`-backed helpers.
    # Both call sites did exactly this before the extraction.
    it "degrades an unknown status to grey instead of raising" do
      expect(helper.ds_debate_state_color("abandoned")).to eq("grey")
      expect(helper.ds_debate_state_color(nil)).to eq("grey")
    end

    it "accepts a symbol as readily as a string" do
      expect(helper.ds_debate_state_color(:declined)).to eq("light-grey")
    end

    # Every tone it can return must be a tone the rest of the system knows about;
    # a colour that exists only here would have no `@source inline` line behind it.
    it "returns only tones the design system already defines" do
      expect(DesignSystemHelper::DEBATE_STATE_COLOR.values.uniq - DesignSystemHelper::TONES)
        .to be_empty
    end
  end

  # The hover row inside a `ui/_menu` panel (DropdownMenu.prompt.md's `MenuItem`).
  # A helper rather than a partial because two of its eleven call sites are a
  # `button_to` and a `<button>` with frozen `data-*` attributes, neither of which a
  # layout partial can wrap — see the note on the constant.
  describe "#ds_menu_item_classes" do
    def tokens(**opts)
      helper.ds_menu_item_classes(**opts).split
    end

    it "is a full-width hover row in the design system's menu grey" do
      expect(tokens).to include("block", "w-full", "text-left", "hover:bg-gray-100")
    end

    # readme.md, VISUAL FOUNDATIONS: "UI text 14px". These rows inherited 16px from the
    # body before Slice 9. Asserted on the token list rather than by name so a stray
    # `text-base` sneaking back in still fails.
    it "is 14px, and carries exactly one type size" do
      expect(tokens).to include("text-sm")
      expect(tokens.grep(/\Atext-(xs|sm|base|lg|xl|2xl)\z/)).to eq(["text-sm"])
    end

    it "is ink by default" do
      expect(tokens).to include("text-black")
    end

    # DropdownMenu.prompt.md: "destructive/report rows take tone=neutral (pink)".
    it "colours a destructive row pink and a disabled one grey" do
      expect(tokens(tone: "neutral")).to include("text-neutral")
      expect(tokens(tone: "grey")).to include("text-grey")
    end

    # The disabled row must NOT light up under the cursor. DropdownMenu.prompt.md gives
    # the hover fill to rows, not to disabled ones, and `grey`'s only call site is the
    # inert `<span>` behind `hujahs/show`'s "Delete hoojah (Slice 2)" — a non-interactive
    # element that highlights on hover claims to be clickable and isn't. The rule lives
    # in the tone rather than in a `hover:` argument, so this is what pins it.
    it "drops the hover fill on the disabled tone, and only on that tone" do
      expect(tokens(tone: "grey")).not_to include("hover:bg-gray-100")
      expect(tokens(tone: "black")).to include("hover:bg-gray-100")
      expect(tokens(tone: "neutral")).to include("hover:bg-gray-100")
    end

    # Splitting the hover out of MENU_ITEM_BASE must not have reordered anything for the
    # two tones that keep it — same utilities, same order, same string.
    it "is unchanged for the two interactive tones" do
      expect(helper.ds_menu_item_classes(tone: "black"))
        .to eq("#{DesignSystemHelper::MENU_ITEM_BASE} #{DesignSystemHelper::MENU_ITEM_HOVER} text-black")
    end

    it "never carries two colours at once" do
      DesignSystemHelper::MENU_ITEM_TONES.each do |tone|
        expect(tokens(tone: tone).grep(/\Atext-(?!sm\z|left\z)/).size).to eq(1)
      end
    end

    # No `fill-` on any tone: ten of the eleven rows have no icon, and `fill-black` is a
    # class no view spells and no `@source inline` line covers. The report row that does
    # have an icon spells `fill-neutral` itself.
    it "emits no fill colour, which would put `fill-black` on ten iconless rows" do
      DesignSystemHelper::MENU_ITEM_TONES.each do |tone|
        expect(tokens(tone: tone).grep(/\Afill-/)).to be_empty
      end
    end

    # A menu row is not a card and not a button: no shadow, no border, no pill.
    it "is a flat row — no shadow, no border, no pill" do
      expect(tokens).not_to include("shadow", "rounded-full")
      expect(tokens.grep(/\Aborder/)).to be_empty
    end

    # Same convention as every helper in this file.
    it "treats a nil tone as unset, and a misspelled one as a typo" do
      expect(helper.ds_menu_item_classes(tone: nil)).to eq(helper.ds_menu_item_classes)
      expect { helper.ds_menu_item_classes(tone: "pink") }
        .to raise_error(ArgumentError, /pink.*#{Regexp.escape(DesignSystemHelper::MENU_ITEM_TONES.join(", "))}/m)
    end

    it "accepts a symbol as readily as a string" do
      expect(helper.ds_menu_item_classes(tone: :neutral)).to eq(helper.ds_menu_item_classes(tone: "neutral"))
    end

    it "degrades to an ink row instead of raising in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      expect(helper.ds_menu_item_classes(tone: "pink")).to eq(helper.ds_menu_item_classes)
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
  # The bundle is gitignored and nothing in the boot path rebuilds it, so
  # `TailwindBuild.emitted?` builds before its first read. It also owns the regex —
  # the `:` escaping and the token boundary that stops `.rounded` matching
  # `.rounded-full` — which all three groups below need and none should restate.
  before(:all) { TailwindBuild.once! }

  # Not `ActionController::Base.helpers` — that proxy carries only Action View's own
  # modules, so it would raise NoMethodError here. Going through ApplicationController
  # also confirms the helper is genuinely mixed into every app view.
  let(:view) { ApplicationController.helpers }

  it "generates every utility the helper can produce, for every variant and tone" do
    wanted = DesignSystemHelper::VARIANTS.product(DesignSystemHelper::TONES).flat_map { |variant, tone|
      %i[md sm].flat_map { |size| view.ds_button_classes(variant: variant, tone: tone, size: size).split }
    }.uniq

    missing = wanted.reject { |klass| TailwindBuild.emitted?(klass) }

    expect(missing).to be_empty,
      "these button utilities are absent from app/assets/builds/tailwind.css — " \
      "add them to the `@source inline(...)` safelist: #{missing.join(", ")}"
  end
end

# The avatar's classes are literal strings in `AVATAR_SIZES`, so Tailwind's source
# scanner does see them and no `@source inline` entry is needed — but "the scanner
# reads .rb files under app/" is an assumption about the scanner's globs, not a
# guarantee, and the failure mode is a silent one: an unstyled 0×0 avatar. `w-11`
# and `text-4xl` are also the two utilities in the set that nothing else in the app
# spells out today, so they are exactly what a narrowed content glob would drop.
RSpec.describe "Avatar utilities reach the compiled bundle" do
  before(:all) { TailwindBuild.once! }

  let(:view) { ApplicationController.helpers }

  it "generates the box and type utilities for every avatar size" do
    wanted = DesignSystemHelper::AVATAR_SIZES.keys
      .flat_map { |size| view.ds_avatar_classes(size: size).split }.uniq

    missing = wanted.reject { |klass| TailwindBuild.emitted?(klass) }

    expect(missing).to be_empty,
      "these avatar utilities are absent from app/assets/builds/tailwind.css: #{missing.join(", ")}"
  end
end

# `ds_card_classes` interpolates the stance into `border-#{stance}` for the 8px left
# border, so — exactly as with the button tones — Tailwind's scanner never sees those
# class names and `@source inline(...)` is the only thing putting them in the bundle.
# The failure mode is quiet: `border-agree` with no rule behind it renders a card that
# merely looks unstanced, which is the design system motif silently going missing.
#
# `border-l-8` is checked alongside them because it is the *width*: the colour without
# it paints nothing, and unlike the colours it is a literal in the partial, so this
# example also catches a content glob that stopped reading `app/views`.
RSpec.describe "Card stance utilities reach the compiled bundle" do
  before(:all) { TailwindBuild.once! }

  let(:view) { ApplicationController.helpers }

  it "generates the left border and every stance colour a card can take" do
    wanted = DesignSystemHelper::CARD_STANCES
      .flat_map { |stance| view.ds_card_classes(stance: stance, padded: true).split }.uniq

    missing = wanted.reject { |klass| TailwindBuild.emitted?(klass) }

    expect(missing).to be_empty,
      "these card utilities are absent from app/assets/builds/tailwind.css — " \
      "add them to the `@source inline(...)` safelist: #{missing.join(", ")}"
  end
end

# `ds_menu_item_classes` interpolates its tone into `text-#{tone}` — same blind spot as
# the button tones and the card stances, and the same quiet failure: `text-neutral` with
# no rule behind it leaves a "Flag this hoojah" row rendered in ordinary ink, which
# reads as a perfectly normal menu entry rather than a destructive one.
#
# `text-black` is the interesting member. Unlike `grey` and `neutral` it is covered by no
# `@source inline(...)` line at all — it survives purely because some view still spells it
# as a literal, and eight later tasks are busy replacing hand-written strings with helper
# calls. The day the last literal goes, this example is what says so.
RSpec.describe "Menu item tone utilities reach the compiled bundle" do
  before(:all) { TailwindBuild.once! }

  let(:view) { ApplicationController.helpers }

  it "generates the row's own utilities and every tone it can take" do
    wanted = DesignSystemHelper::MENU_ITEM_TONES
      .flat_map { |tone| view.ds_menu_item_classes(tone: tone).split }.uniq

    missing = wanted.reject { |klass| TailwindBuild.emitted?(klass) }

    expect(missing).to be_empty,
      "these menu utilities are absent from app/assets/builds/tailwind.css — " \
      "add them to the `@source inline(...)` safelist: #{missing.join(", ")}"
  end
end

# `ds_debate_state_color` is not itself a class — both call sites interpolate its
# return into `text-#{...}`, which is the same blind spot as the button tones and the
# card stances, and the same quiet failure: `text-light-grey` with no rule behind it
# leaves a declined debate labelled in the browser's default ink, which reads as a
# perfectly ordinary label rather than the faintest state in the set.
#
# Derived from the constant rather than restated, so a fifth debate state added to the
# map is covered here the moment it exists.
RSpec.describe "Debate state colour utilities reach the compiled bundle" do
  before(:all) { TailwindBuild.once! }

  it "generates the text colour of every state a debate can be in" do
    wanted = DesignSystemHelper::DEBATE_STATE_COLOR.values.uniq.map { |tone| "text-#{tone}" }

    missing = wanted.reject { |klass| TailwindBuild.emitted?(klass) }

    expect(missing).to be_empty,
      "these debate state utilities are absent from app/assets/builds/tailwind.css — " \
      "add them to the `@source inline(...)` safelist: #{missing.join(", ")}"
  end
end
