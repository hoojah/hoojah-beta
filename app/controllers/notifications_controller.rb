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

  # Mark read, then bounce to the related hoojah. The redirect target is always an
  # internal `hujah_path` (never a user-supplied URL) — no open-redirect.
  def update
    authorize @notification
    @notification.update!(read: true)
    if @notification.hujah
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
