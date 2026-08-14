# The single source of truth for Hoojah's button idiom.
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
  # permitted set is a typo, and raises; see `ds_button_option`.
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
    variant = ds_button_option(variant&.to_sym, :outline, VARIANTS, "variant")
    size = ds_button_option(size&.to_sym, :md, SIZES, "size")
    tone = ds_button_option(tone&.to_s, "primary", TONES, "tone")
    sizing = (size == :sm) ? "px-4 py-1 text-sm" : "px-5 py-2 text-base"
    [BASE, ds_button_variant(variant, tone, sizing)].join(" ")
  end

  private

  # Unset takes the default; a typo is loud. `tone: "aggree"` is the dangerous case —
  # silently degrading it renders a perfectly ordinary primary button, so neither code
  # review nor CI ever catches it and the wrong colour ships. A variant typo at least
  # comes out a visibly wrong shape. Raise where a human or a test will see it; in
  # production a wrong colour still beats a 500 on a page that was otherwise fine.
  def ds_button_option(value, default, permitted, name)
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
