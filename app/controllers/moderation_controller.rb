class ModerationController < ApplicationController
  before_action :authenticate_user!

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
end
