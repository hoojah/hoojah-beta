class ModerationController < ApplicationController
  before_action :authenticate_user!
  # Authorize BEFORE loading the record (M-1). set_hujah runs last so a non-staff
  # member is denied identically for an existing slug and a missing one — otherwise
  # set_hujah's RecordNotFound (404) vs the Pundit redirect (existing) is an existence
  # oracle for removed slugs. require_moderator! authorizes each action once, so
  # verify_authorized stays satisfied and no in-action authorize is needed.
  before_action :require_moderator!
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
    base = Hujah.joins(:flags).where(flags: {status: Flag.statuses[:pending]})
      .group("hujahs.id")
      .select("hujahs.*")
      .order(Arel.sql("MIN(flags.created_at) ASC"))
      .preload(:user, :flags)
    @pagy, @hujahs = pagy(:countless, base)
  end

  # Resolve every pending report; content untouched, no author notification.
  def dismiss
    @hujah.dismiss_flags!(by: current_user)
    respond_resolved
  end

  # Hide the hujah from everyone but staff + tell the author. Composition (transaction,
  # anonymous notification, removal idempotency) lives on Hujah#remove!.
  def remove
    @hujah.remove!(by: current_user)
    respond_resolved
  end

  # Content untouched; author notified (anonymously); reports closed as actioned.
  def warn
    @hujah.warn_author!(by: current_user)
    respond_resolved
  end

  private

  # Runs before set_hujah for every action (including index). `action_name` maps to the
  # matching policy predicate (index?/dismiss?/remove?/warn?), so this authorizes exactly
  # once per request — the in-action authorize calls are gone and verify_authorized holds.
  def require_moderator!
    authorize :moderation, "#{action_name}?"
  end

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
