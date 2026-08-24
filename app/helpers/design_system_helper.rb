# The single source of truth for Hoojah's button idiom, and for the avatar box
# behind `app/views/ui/_avatar.html.erb`.
#
# The house style is a PILL with a 2px coloured border, white fill and coloured text,
# pressed with `active:scale-95` — see docs/design-system/components/core/Button.jsx
# and Button.prompt.md, which this mirrors. Before Slice 9 that string was hand-typed
# into roughly 75 views, so a border width or a shadow drifted every time somebody
# copy-pasted a button. Change it here now.
#
# NOTE for Tailwind: the tone is *interpolated* into `bg-`/`text-`/`border-`,
# which the source scanner cannot see. Every tone in TONES must stay covered by the
# `@source inline(...)` safelist in app/assets/tailwind/application.css, or the class
# lands in the markup and no rule exists for it. spec/helpers/design_system_helper_spec.rb
# checks the compiled bundle for exactly that.
module DesignSystemHelper
  # The closed set from the design system. `tone` exists so a CTA can inherit the
  # viewer's stance — "Add hoojah" on a hujah you agreed with is agree-coloured — which
  # is why the stance trio sits alongside `primary` and the two greys.
  TONES = %w[primary agree neutral disagree grey light-grey].freeze

  # Public so callers and specs can enumerate the set rather than restating it.
  # `on_primary` / `on_primary_outline` are for the blue profile header ONLY.
  VARIANTS = %i[outline solid rect on_primary on_primary_outline link].freeze

  SIZES = %i[md sm].freeze

  BASE = "inline-flex items-center justify-center gap-1 no-underline cursor-pointer " \
         "transition active:scale-95 disabled:opacity-50 disabled:cursor-default".freeze

  # `nil` means "unset" and takes the default: views reach for
  # `ds_button_classes(variant: local_assigns[:variant])`, and a `local_assigns` miss is
  # nil — a plain button beats a 500 over an unpassed local. A non-nil value outside the
  # permitted set is a typo, and raises; see `ds_option`.
  #
  # Note that `size:` sets TYPE as well as padding — `:sm` is `text-sm`, `:md` is
  # `text-base` — because Button.jsx pins the font size per size. That is the design
  # system's contract, not an accident of this helper. Two views currently use
  # `px-4 py-1` with no `text-sm`; that is pre-existing drift, and moving them onto
  # `size: :sm` corrects them rather than regressing them.
  #
  # The ONE exception is `link`, which carries no font size at all and inherits from its
  # context. This is deliberate — do not "fix" it by adding `text-base`. Link buttons are
  # the bare text controls inside notification rows (Accept / Decline / Mark as read),
  # which sit in a 14px context; emitting `text-base` would visibly enlarge them against
  # the surrounding row. Button.jsx puts a font size on every variant because it is a
  # React component that owns its own box, whereas this helper returns a class string
  # onto someone else's element, so inheriting is the better behaviour here.
  def ds_button_classes(variant: :outline, tone: "primary", size: :md)
    variant = ds_option(variant&.to_sym, :outline, VARIANTS, "variant")
    size = ds_option(size&.to_sym, :md, SIZES, "size")
    tone = ds_option(tone&.to_s, "primary", TONES, "tone")
    sizing = (size == :sm) ? "px-4 py-1 text-sm" : "px-5 py-2 text-base"
    [BASE, ds_button_variant(variant, tone, sizing)].join(" ")
  end

  # Box + type for `ui/_avatar`, keyed by the five sizes the product uses
  # (Avatar.prompt.md): 96 profile header, 44 hujah header + composer, 40 follower
  # row, 36 navbar, 32 compact card / debate turn / parent stub.
  #
  # The font size is here rather than as one shared class on the partial because
  # Avatar.jsx sets it to `Math.round(size * 0.38)` — the initials scale with the
  # circle, and 16px letters in a 32px circle overflow it. Tailwind's scale cannot hit
  # 17/15/14/12 exactly, so each size takes the nearest step (worst case 1.2px off, on
  # `row`); off-scale `text-[17px]` values would buy that pixel at the cost of putting
  # type outside the `@theme` scale, which is not a trade this design system makes.
  AVATAR_SIZES = {
    lg: "w-24 h-24 text-4xl",   # 96px — DS 36px
    md: "w-11 h-11 text-base",  # 44px — DS 17px
    row: "w-10 h-10 text-sm",   # 40px — DS 15px
    nav: "w-9 h-9 text-sm",     # 36px — DS 14px
    sm: "w-8 h-8 text-xs"       # 32px — DS 12px
  }.freeze

  # Same contract as `ds_button_classes`: nil is an unpassed local and takes the
  # default; anything else outside the set is a typo and says so.
  #
  # `to_s.to_sym`, not `to_sym`, because Avatar.prompt.md documents these sizes as the
  # pixel numbers 96/44/40/36/32 — so `size: 44` is the likeliest typo of all, and
  # `Integer#to_sym` does not exist. Coercing through a string routes it into the same
  # named error as any other unknown size instead of a bare NoMethodError.
  def ds_avatar_classes(size: :md)
    AVATAR_SIZES.fetch(ds_option(size&.to_s&.to_sym, :md, AVATAR_SIZES.keys, "size"))
  end

  # The 8px coloured left border of a compact card — Card.prompt.md and the design
  # system's VISUAL FOUNDATIONS both call it "a real motif of this brand".
  #
  # `stance` is the design system's name for it, but the closed set is wider than the
  # stance trio, because three different surfaces reach for the same motif:
  # `hujahs/_child_card` and `users/_user_hujah` colour it by the responder's vote;
  # `hujahs/_parent_card` falls back to `primary` when the viewer never voted; and
  # `notifications/_notification_card` borrows it for read/unread. Narrowing this to
  # agree/neutral/disagree would leave two of those three unable to use `ui/_card` at
  # all, so the set is what the product renders, not what the word "stance" implies.
  #
  # Every value is interpolated into `border-#{...}`, which the Tailwind scanner cannot
  # see — all six must stay in the `@source inline(...)` safelist, and the bundle spec
  # in spec/helpers/design_system_helper_spec.rb derives its expectation from here.
  CARD_STANCES = %w[agree neutral disagree primary read unread].freeze

  # SQUARE-cornered, `shadow`. Card.prompt.md's first line is "Never round a
  # feed card", so there is deliberately no rounding class and no way to ask for one.
  # The fill is `bg-card` (a theme-aware token, Hoojah 2026) rather than `bg-white`:
  # cards are the surface body text sits on, so a pinned white would leave dark-mode
  # ink invisible on a still-white card. `bg-card` chains to `--card`, which the
  # [data-theme]/[data-scheme] blocks retint. `text-white` glyph inversions are
  # unaffected — white stays fixed.
  CARD_BASE = "shadow bg-card".freeze

  # Backs `app/views/ui/_card.html.erb`. Same contract as the two helpers above: a nil
  # stance is an unpassed local and means "no left border"; a non-nil one outside the
  # set is a typo and says so. That last part is why this is a helper rather than
  # string interpolation in the partial — `stance: "aggree"` interpolated raw yields
  # `border-aggree`, a class with no rule behind it, so the card renders looking merely
  # unstanced and neither review nor CI ever sees it.
  def ds_card_classes(stance: nil, padded: false)
    stance = ds_option(stance&.to_s, nil, CARD_STANCES, "stance")
    [CARD_BASE,
      ("border-l-8 border-#{stance}" if stance),
      ("px-4 py-3" if padded)].compact.join(" ")
  end

  # The debate state label's colour — `DEBATE_STATE_COLOR` in
  # docs/design-system/components/debate/DebateCard.jsx, which exports it precisely
  # because two components consume it: `DebateCard` (the row in a hoojah's Debates
  # lens) and `DebateStatus` (the label on the transcript screen). DebateCard.prompt.md
  # calls the mapping FIXED — "pending → agree orange, active → indigo, concluded →
  # grey, declined → light-grey".
  #
  # Before Slice 9 Task 4.5's review, `debates/_debate_card` and `debates/_debate_status`
  # each carried their own copy of this hash inline, and nothing anywhere asserted
  # either one. A one-sided edit — recolouring `declined` on the card and not on the
  # transcript, or vice versa — was therefore invisible: both files still rendered a
  # valid class, the suite stayed green, and the same debate read as two different
  # states depending on which screen you were looking at.
  #
  # A HELPER rather than a shared partial, deliberately. `_debate_status` is rendered
  # from `broadcast_replace_later_to`, i.e. inside an ActiveJob with no request and no
  # `current_user`; a partial pulled into that path is one more thing that can raise
  # where nobody sees it. Helpers are broadcast-safe — `ApplicationController.render`
  # carries the full helper module — and `IconsHelper#stance_color` is the existing
  # precedent for exactly this shape, already called from broadcast-rendered partials.
  DEBATE_STATE_COLOR = {
    "pending" => "agree",
    "active" => "primary",
    "concluded" => "grey",
    "declined" => "light-grey"
  }.freeze

  # Unlike the `ds_option`-backed helpers above, an unknown status DEGRADES to grey
  # rather than raising, and does so in every environment. That is not a lapse in the
  # convention — the argument here is not a designer's typo in a view but
  # `debates.status`, whose value comes from the model's enum. A status this map has
  # not been taught about is a schema change, and the honest render of "a state the
  # design system has no colour for" is the neutral one. Both call sites behaved this
  # way before the extraction (`MAP[debate.status] || "grey"`); it is preserved.
  #
  # `text-#{...}` is interpolated at both call sites, so all four values must stay
  # covered by the `@source inline(...)` safelist in app/assets/tailwind/application.css.
  # The stance line covers agree and primary, the grey line covers the other two, and
  # spec/helpers/design_system_helper_spec.rb checks the compiled bundle for all four.
  def ds_debate_state_color(status) = DEBATE_STATE_COLOR.fetch(status.to_s, "grey")

  # The hover row inside a `ui/_menu` panel — DropdownMenu.prompt.md's `MenuItem`.
  # Eleven rows across three files spell this string by hand today.
  #
  # This is a HELPER and not a `ui/_menu_item` partial, which is the obvious thing to
  # reach for and does not work here. Of those eleven rows, one is a `button_to` (navbar
  # Log Out) and one is a `<button>` carrying frozen `data-share-target` /
  # `data-action` attributes (`hujahs/_share_menu`); the rest are `link_to` / `mail_to`.
  # `button_to` emits its own `<form>` + `<button>` and cannot be wrapped by a layout
  # partial at all — moving it would mean rewriting a form whose action and verb are
  # frozen. So the only seam every row shares is the class string, which is exactly the
  # case `ui/_card`'s header already carves out for `ds_card_classes`: "If your card IS
  # a link … call `ds_card_classes` directly on the `link_to` instead; that is the
  # supported escape hatch." Same shape, one step further — here every call site is that
  # escape hatch, so there is no partial left to write.
  #
  # `text-sm` is baked in: the design system puts UI text at 14px (readme.md, VISUAL
  # FOUNDATIONS) and these rows inherited 16px from the body. One string is what makes
  # that a single edit rather than eleven.
  #
  # `block` is likewise baked in, and `hujahs/show`'s report row wants `flex items-center
  # gap-1` instead. That override DOES work — Tailwind emits the display utilities in its
  # own fixed order, and `.block` comes before `.flex` in it, so the caller's `flex` is the
  # later rule and wins — but it works by bundle order rather than by call order, which is
  # the `ui/_card` `padded:` trap wearing a different hat. Pass a different display only
  # knowing that; do not pass a second *padding* or *width*.
  #
  # The RELATIVE ORDER is the load-bearing fact and the only thing pinned here. Byte
  # offsets deliberately are not: every bundle change moves them, so a number in this
  # comment rots the next time anyone adds a utility. To re-verify after a build, ask the
  # bundle which comes first rather than where either one sits:
  #
  #   bin/rails tailwindcss:build
  #   grep -bo -e '[.]block{' -e '[.]flex{' app/assets/builds/tailwind.css | head -2
  #
  # The block rule must print first. If it ever prints second, the report row silently
  # goes back to `display:block` and nothing else in the suite will notice.
  #
  # The one row that legitimately ignores `block` without saying so is `_share_menu`'s
  # native-share `<button hidden>`. It stays invisible because Tailwind v4's preflight
  # declares `[hidden]:where(:not([hidden="until-found"])){display:none !important}`, and
  # `!important` outranks the utility. That is load-bearing: the share controller toggles
  # the ATTRIBUTE, not a class, so without preflight's `!important` this row would render
  # `display:block` on every device the Web Share API is missing from.
  MENU_ITEM_BASE = "block w-full text-left px-3 py-1 text-sm rounded no-underline".freeze

  # Split out of the base so `tone: "grey"` can drop it. See `ds_menu_item_classes`.
  MENU_ITEM_HOVER = "hover:bg-gray-100".freeze

  # Narrower than TONES on purpose, and not a subset of it either. A menu row is ink by
  # default; `grey` is the disabled row (`hujahs/show`'s "Delete hoojah (Slice 2)"); and
  # `neutral` is DropdownMenu.prompt.md's rule that "destructive/report rows take
  # tone=neutral (pink)". Nothing renders an agree-coloured or primary-coloured menu row,
  # and offering one would invite a menu that looks like a stance.
  MENU_ITEM_TONES = %w[ink grey neutral].freeze

  # Same contract as every helper above: nil is an unpassed local and takes the default,
  # anything else outside the set is a typo and says so.
  #
  # No `fill-<tone>` is emitted, and none should be added — a wrapper's fill never
  # reached the row's Lucide glyph. See the tombstone in app/assets/tailwind/application.css.
  #
  # `grey` DROPS the hover fill, and does so from the tone rather than from a `hover:`
  # keyword. DropdownMenu.prompt.md says "rows hover to `--color-gray-100`"; it does not
  # say disabled rows do, and grey is not a colour choice here — MENU_ITEM_TONES defines
  # it as the disabled state, whose only call site is the inert `<span>` behind
  # `hujahs/show`'s "Delete hoojah (Slice 2)". A non-interactive row that lights up under
  # the cursor claims to be clickable and isn't. Encoding that in the tone keeps the
  # helper one-argument and makes the rule impossible to get wrong at a call site; a
  # `hover:` boolean would be a second thing every one of the eleven callers has to
  # decide, to express something the tone already means. The emitted string for the other
  # two tones is byte-identical to before the split.
  def ds_menu_item_classes(tone: "ink")
    tone = ds_option(tone&.to_s, "ink", MENU_ITEM_TONES, "tone")
    [MENU_ITEM_BASE, (MENU_ITEM_HOVER unless tone == "grey"), "text-#{tone}"].compact.join(" ")
  end

  # The avatar's fallback when a user has no photo. Two letters, because three do not
  # fit a 32px circle and Malaysian names run long ("Nurul Izzah binti Anwar"). A name
  # that yields nothing — blank, whitespace, nil — gets `?` rather than an empty
  # circle, which would just look like a rendering bug.
  def ds_initials(name)
    parts = name.to_s.strip.split(/\s+/).first(2)
    return "?" if parts.empty?
    parts.filter_map { |word| word[0] }.join.upcase
  end

  private

  # Unset takes the default; a typo is loud. `tone: "aggree"` is the dangerous case —
  # silently degrading it renders a perfectly ordinary primary button, so neither code
  # review nor CI ever catches it and the wrong colour ships. A variant typo at least
  # comes out a visibly wrong shape. Raise where a human or a test will see it; in
  # production a wrong colour still beats a 500 on a page that was otherwise fine.
  def ds_option(value, default, permitted, name)
    return default if value.nil?
    return value if permitted.include?(value)
    unless Rails.env.production?
      raise ArgumentError, "unknown #{name} #{value.inspect}; expected one of #{permitted.join(", ")}"
    end
    default
  end

  # Private on purpose: this is an implementation detail of `ds_button_classes`, not a
  # view-level API. Being a module mixed into the view context, `private` stops
  # `helper.ds_button_variant` and `ActionController::Base.helpers.ds_button_variant`;
  # it cannot stop an implicit-receiver call from inside an ERB template, so treat it
  # as the boundary marker it is.
  def ds_button_variant(variant, tone, sizing)
    case variant
    when :solid then "#{sizing} rounded-full bg-#{tone} text-white shadow"
    when :rect then "#{sizing} rounded bg-#{tone} text-white"
    # on_primary/on_primary_outline: for the blue profile header ONLY. They are locked
    # to white-on-primary and to the small size — `tone:` and `size:` do not reach them,
    # because there is exactly one surface they may appear on.
    when :on_primary then "px-4 py-1 text-sm rounded-full bg-white text-primary"
    when :on_primary_outline then "px-4 py-1 text-sm rounded-full border border-white text-white bg-transparent"
    when :link then "border-0 bg-transparent p-0 text-#{tone}"
    # The house pill: `bg-card` (theme-aware, Hoojah 2026) not a pinned `bg-white`, so
    # the fill retints in dark mode instead of staying white. The 2px stance border and
    # `text-#{tone}` still carry the identity; `on_primary` above keeps its literal
    # `bg-white` on purpose — it sits on the blue profile header, a colour surface, not a
    # card.
    else "#{sizing} rounded-full border-2 border-#{tone} text-#{tone} bg-card shadow"
    end
  end
end
