class ModerationController < ApplicationController
  before_action :authenticate_user!
  before_action :set_hujah, except: :index

  # The staff review queue: hujahs with >= 1 pending flag, oldest pending report first,
  # one row per hujah. GROUP BY collapses many flags into one row; preload(:user, :flags)
  # loads them via SEPARATE queries so the grouping is undisturbed. (`includes` here
  # promotes to an eager LEFT JOIN whose users.id then violates GROUP BY; `preload` never
  # joins.) The view recomputes count/breakdown/earliest in Ruby from the preloaded
  # :flags, so no aggregate SELECT columns are needed — only `hujahs.*` plus the
  # MIN(flags.created_at) ORDER BY, which stands alone without an alias. pagy(:countless).
  #
  # Deliberately NOT swept by `not_removed`: the queue queries by pending flags, so an
  # already-removed hujah with outstanding reports still surfaces here — staff are the
  # one audience that reads removed content.
  def index
    authorize :moderation, :index?
    base = Hujah.joins(:flags).where(flags: {status: Flag.statuses[:pending]})
      .group("hujahs.id")
      .select("hujahs.*")
      .order(Arel.sql("MIN(flags.created_at) ASC"))
      .preload(:user, :flags)
    @pagy, @hujahs = pagy(:countless, base)
  end

  # Resolve every pending report; content untouched, no author notification.
  def dismiss
    authorize :moderation, :dismiss?
    @hujah.dismiss_flags!(by: current_user)
    respond_resolved
  end

  # Hide the hujah from everyone but staff + tell the author. Composition (transaction,
  # anonymous notification, removal idempotency) lives on Hujah#remove!.
  def remove
    authorize :moderation, :remove?
    @hujah.remove!(by: current_user)
    respond_resolved
  end

  # Content untouched; author notified (anonymously); reports closed as actioned.
  def warn
    authorize :moderation, :warn?
    @hujah.warn_author!(by: current_user)
    respond_resolved
  end

  private

  def set_hujah
    @hujah = Hujah.friendly.find(params[:slug])
  end

  def respond_resolved
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to moderation_path, status: :see_other }
    end
  end
end
