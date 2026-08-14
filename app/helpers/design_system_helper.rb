# The single source of truth for Hoojah's button idiom, and for the avatar box
# behind `app/views/ui/_avatar.html.erb`.
#
# The house style is a PILL with a 2px coloured border, white fill and coloured text,
# pressed with `active:scale-95` — see docs/design-system/components/core/Button.jsx
# and Button.prompt.md, which this mirrors. Before Slice 9 that string was hand-typed
# into roughly 75 views, so a border width or a shadow drifted every time somebody
# copy-pasted a button. Change it here now.
#
# NOTE for Tailwind: the tone is *interpolated* into `bg-`/`text-`/`border-`/`fill-`,
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
  def ds_avatar_classes(size: :md)
    AVATAR_SIZES.fetch(ds_option(size&.to_sym, :md, AVATAR_SIZES.keys, "size"))
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

  # White, SQUARE-cornered, `shadow`. Card.prompt.md's first line is "Never round a
  # feed card", so there is deliberately no rounding class and no way to ask for one.
  CARD_BASE = "shadow bg-white".freeze

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
    when :solid then "#{sizing} rounded-full bg-#{tone} text-white fill-white shadow"
    when :rect then "#{sizing} rounded bg-#{tone} text-white fill-white"
    # on_primary/on_primary_outline: for the blue profile header ONLY. They are locked
    # to white-on-primary and to the small size — `tone:` and `size:` do not reach them,
    # because there is exactly one surface they may appear on.
    when :on_primary then "px-4 py-1 text-sm rounded-full bg-white text-primary fill-primary"
    when :on_primary_outline then "px-4 py-1 text-sm rounded-full border border-white text-white fill-white bg-transparent"
    when :link then "border-0 bg-transparent p-0 text-#{tone} fill-#{tone}"
    else "#{sizing} rounded-full border-2 border-#{tone} text-#{tone} fill-#{tone} bg-white shadow"
    end
  end
end
