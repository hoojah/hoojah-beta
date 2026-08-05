module IconsHelper
  STANCE_ICON = { 'agree' => 'thumbs-up', 'neutral' => 'minus', 'disagree' => 'thumbs-down' }.freeze

  def stance_icon(stance, **opts)
    lucide_icon(STANCE_ICON.fetch(stance.to_s), **opts)
  end
end
