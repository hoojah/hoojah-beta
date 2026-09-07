module IconsHelper
  STANCE_ICON = {"agree" => "thumbs-up", "neutral" => "minus", "disagree" => "thumbs-down"}.freeze

  # Per-post visibility badge, top-level claims only (replies inherit the parent's
  # visibility, so callers guard on parent_id.nil?). visible_public maps to NOTHING
  # by design: public is the default state of the feed, so an icon here always
  # means "restricted". nil-for-public is the contract, not a lapse — unlike
  # stance_icon above, where nil input is a caller bug.
  VISIBILITY_ICON = {"followers_only" => "users", "private_only" => "lock"}.freeze

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

  def visibility_icon(hujah, **opts)
    name = VISIBILITY_ICON[hujah.visibility]
    lucide_icon(name, **opts) if name
  end

  def visibility_title(hujah)
    case hujah.visibility
    when "followers_only" then "Only people following @#{hujah.user.username} can see this"
    when "private_only" then "Only @#{hujah.user.username} can see this"
    end
  end
end
