class Api::V1::NotificationsController < Api::V1::BaseController
  before_action :authenticate_user!

  def index
    skip_authorization
    notifications = policy_scope(Notification).order(created_at: :asc)

    serialized_notifications = NotificationSerializer.new(notifications, params: {logged_in: user_signed_in?, current_user_id: current_user.id}).serializable_hash

    render json: serialized_notifications
  end

  def update
    authorize notification
    if notification.update!(read: notification_params[:read])
      render json: {
        status: 200
      }
    else
      render json: notification.errors
    end
  end

  def destroy
    authorize notification
    notification.destroy
    render json: {
      message: "Notification deleted!",
      status: 200
    }
  end

  private

  def notification_params
    params[:notification].permit(:read)
  end

  def notification
    @notification ||= Notification.find(params[:id])
  end
end
