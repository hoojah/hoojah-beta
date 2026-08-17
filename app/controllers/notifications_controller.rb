class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: [:update, :destroy]

  # Always the signed-in user's own notifications (no username in the URL). The
  # policy scope enforces this, so `skip_authorization` covers `verify_authorized`.
  def index
    skip_authorization
    @notifications = policy_scope(Notification)
      .includes(:hujah, :subject_user)
      .order(created_at: :desc)
  end

  # Mark read, then bounce to whatever the notification is about. The debate wins the
  # precedence because all four `debate_*` categories set BOTH `debate_id` and
  # `hujah_id` (see `Debate#notify`) and the debate is the thing that happened — the
  # hoojah is only the claim it grew out of. Both targets are internal slug paths,
  # never user-supplied, so neither branch is an open-redirect.
  #
  # No extra visibility guard on the debate branch: `Debate#notify`'s recipient is by
  # construction a participant, and `DebatePolicy#show?` is
  # `record.participant?(user) || (record.concluded? && …)` — the participant branch
  # admits them unconditionally in every status, `declined` included. `DebatesController#show`
  # re-authorizes on arrival anyway. The two branches are NOT equivalent in how they
  # fail, though: `DebatesController` has its own `rescue_from Pundit::NotAuthorizedError`
  # that renders a flat 403, where `hujahs#show` inherits the app-wide friendly
  # redirect-back-with-alert. So a pathological row would degrade harder here. It is
  # unreachable given the above, but don't read the two branches as behaving alike.
  #
  # `belongs_to :debate, optional: true` means a deleted debate simply falls through
  # to the hoojah branch.
  def update
    authorize @notification
    @notification.update!(read: true)
    if @notification.debate
      redirect_to debate_path(@notification.debate.slug), status: :see_other
    elsif @notification.hujah
      redirect_to hujah_path(@notification.hujah.slug), status: :see_other
    else
      redirect_to notifications_path, status: :see_other
    end
  end

  def destroy
    authorize @notification
    @notification.destroy

    respond_to do |format|
      format.turbo_stream # destroy.turbo_stream.erb — removes dom_id(@notification)
      format.html { redirect_to notifications_path, status: :see_other }
    end
  end

  private

  def set_notification
    @notification = Notification.find(params[:id])
  end
end
