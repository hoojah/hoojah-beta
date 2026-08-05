# The single authorized real-time channel for a debate (Slice 8, 2b). Turbo
# broadcasts flow over Turbo::StreamsChannel; we subclass it so every
# subscription re-checks DebatePolicy#show? at subscribe time — an ACTIVE
# debate streams to participants only, a CONCLUDED one to anyone who may read
# the transcript (both participants visible). Auth here mirrors the HTTP gate.
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
