# The single authorized real-time channel for a debate (Slice 8, 2b). Turbo
# broadcasts flow over Turbo::StreamsChannel; we subclass it so every
# subscription re-checks DebatePolicy#show? at subscribe time. Auth here
# mirrors the HTTP gate exactly, so it changes shape with it: since Hoojah 2026
# Task 3.5, an ACTIVE debate streams to its participants AND to any spectator
# who could already read a CONCLUDED transcript of it (both participants +
# the underlying claim visible) — the spectator view renders a live
# transcript, so it needs the live stream. A PENDING debate still streams to
# participants only.
class DebateChannel < Turbo::StreamsChannel
  def subscribed
    # split(":").first takes the LEADING streamable of a (possibly composite
    # [debate, user]) stream name; today turbo_stream_from @debate always signs a
    # single streamable, so this is just the debate's to_gid_param.
    debate = GlobalID::Locator.locate(verified_stream_name_from_params&.split(":")&.first)

    if debate.is_a?(Debate) && DebatePolicy.new(current_user, debate).show?
      super
    else
      reject
    end
  rescue ActiveRecord::RecordNotFound
    # The signed name is valid but the Debate was since deleted — fail closed.
    reject
  end
end
