module IconsHelper
  STANCE_ICON = {"agree" => "thumbs-up", "neutral" => "minus", "disagree" => "thumbs-down"}.freeze

  # A stance's design-system colour token, for feeding `ds_button_classes(tone:)` so a
  # CTA inherits the viewer's stance. Anything that is not a stance — no vote yet, nil —
  # is brand primary, so callers never have to branch on "did they vote".
  STANCE_COLOR = {"agree" => "agree", "neutral" => "neutral", "disagree" => "disagree"}.freeze

  def stance_icon(stance, **opts)
    lucide_icon(STANCE_ICON.fetch(stance.to_s), **opts)
  end

  def stance_color(stance) = STANCE_COLOR.fetch(stance.to_s, "primary")
end
