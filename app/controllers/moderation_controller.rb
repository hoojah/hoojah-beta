class ModerationController < ApplicationController
  before_action :authenticate_user!
  before_action :set_hujah, except: :index

  # The staff review queue: hujahs with >= 1 pending flag, oldest pending report first,
  # one row per hujah. GROUP BY + aggregate select collapses many flags into one row;
  # preload(:user, :flags) loads them via SEPARATE queries so the grouping is undisturbed.
  # (`includes` here promotes to an eager LEFT JOIN whose users.id then violates GROUP BY;
  # `preload` never joins.) pagy(:countless, ...) per house rule.
  #
  # Deliberately NOT swept by `not_removed`: the queue queries by pending flags, so an
  # already-removed hujah with outstanding reports still surfaces here — staff are the
  # one audience that reads removed content.
  def index
    authorize :moderation, :index?
    base = Hujah.joins(:flags).where(flags: {status: Flag.statuses[:pending]})
      .group("hujahs.id")
      .select("hujahs.*, COUNT(flags.id) AS pending_flag_count, MIN(flags.created_at) AS earliest_flagged_at")
      .order(Arel.sql("MIN(flags.created_at) ASC"))
      .preload(:user, :flags)
    @pagy, @hujahs = pagy(:countless, base)
  end

  # Resolve every pending report; content untouched, no author notification.
  def dismiss
    authorize :moderation, :dismiss?
    resolve_pending_flags(as: :dismissed)
    respond_resolved
  end

  # Hide the hujah from everyone but staff + tell the author. One transaction: a
  # half-applied removal (hidden but unresolved flags, or the reverse) must not exist.
  # The notification carries NO subject_user_id — the moderator is never identified,
  # the same secret-ballot rule the vote notification follows.
  def remove
    authorize :moderation, :remove?
    ActiveRecord::Base.transaction do
      @hujah.update!(moderation_status: :removed)
      resolve_pending_flags(as: :actioned)
      Notification.create!(user_id: @hujah.user_id, category: :moderation_removed, hujah_id: @hujah.id)
    end
    respond_resolved
  end

  # Content untouched; author notified (anonymously); reports closed as actioned.
  def warn
    authorize :moderation, :warn?
    ActiveRecord::Base.transaction do
      resolve_pending_flags(as: :actioned)
      Notification.create!(user_id: @hujah.user_id, category: :moderation_warning, hujah_id: @hujah.id)
    end
    respond_resolved
  end

  private

  def set_hujah
    @hujah = Hujah.friendly.find(params[:slug])
  end

  # Idempotent by construction: a second call finds zero pending flags and resolves
  # nothing, so re-submitting an already-handled item never raises.
  def resolve_pending_flags(as:)
    @hujah.flags.pending.find_each { |flag| flag.resolve!(by: current_user, as: as) }
  end

  def respond_resolved
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to moderation_path, status: :see_other }
    end
  end
end
