module IconsHelper
  STANCE_ICON = {"agree" => "thumbs-up", "neutral" => "minus", "disagree" => "thumbs-down"}.freeze

  def stance_icon(stance, **opts)
    lucide_icon(STANCE_ICON.fetch(stance.to_s), **opts)
  end

  # A stance's design-system colour token, for feeding `ds_button_classes(tone:)` so a
  # CTA inherits the viewer's stance. The token IS the stance name, so this is only a
  # membership test plus a default — anything that is not a stance, above all `nil` for
  # "hasn't voted", is brand primary, and callers never branch on "did they vote".
  #
  # Its sibling is deliberately less forgiving: `stance_icon(nil)` raises KeyError on
  # that bare `fetch`, because there is no icon that means "no stance". Do not read the
  # default below as the house style for this file.
  def stance_color(stance) = STANCE_ICON.key?(stance.to_s) ? stance.to_s : "primary"
end
