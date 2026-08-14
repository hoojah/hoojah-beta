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

  BASE = "inline-flex items-center justify-center gap-1 no-underline cursor-pointer transition active:scale-95".freeze

  # All three arguments degrade to their default rather than raising, including on
  # `nil`. Views reach for `ds_button_classes(variant: local_assigns[:variant])`, and a
  # `local_assigns` miss is `nil` — a button that renders in the house style beats one
  # that takes the page down over an unpassed local.
  def ds_button_classes(variant: :outline, tone: "primary", size: :md)
    variant = (variant || :outline).to_sym
    size = (size || :md).to_sym
    tone = TONES.include?(tone.to_s) ? tone.to_s : "primary"
    pad = (size == :sm) ? "px-4 py-1 text-sm" : "px-5 py-2"
    [BASE, ds_button_variant(variant, tone, pad)].join(" ")
  end

  private

  # Private on purpose: this is an implementation detail of `ds_button_classes`, not a
  # view-level API. Being a module mixed into the view context, `private` stops
  # `helper.ds_button_variant` and `ActionController::Base.helpers.ds_button_variant`;
  # it cannot stop an implicit-receiver call from inside an ERB template, so treat it
  # as the boundary marker it is. An unknown variant falls through to the house style.
  def ds_button_variant(variant, tone, pad)
    case variant
    when :solid then "#{pad} rounded-full bg-#{tone} text-white fill-white shadow"
    when :rect then "#{pad} rounded bg-#{tone} text-white fill-white"
    when :on_primary then "px-4 py-1 text-sm rounded-full bg-white text-primary fill-primary"
    when :on_primary_outline then "px-4 py-1 text-sm rounded-full border border-white text-white fill-white bg-transparent"
    when :link then "border-0 bg-transparent p-0 text-#{tone} fill-#{tone}"
    else "#{pad} rounded-full border-2 border-#{tone} text-#{tone} fill-#{tone} bg-white shadow"
    end
  end
end
