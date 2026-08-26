class Api::V1::NotificationsController < Api::V1::BaseController
  before_action :authenticate_user!

  # `notification_params` uses `require`, so a PATCH with no `notification` key raises
  # ParameterMissing. Production maps that to 400 via `rescue_responses`, but the app
  # runs `show_exceptions=:none` in test so the raise propagates — rescue here to
  # return the 400 the request spec asserts (same in-controller-rescue pattern as
  # Api::V1::FlagsController).
  rescue_from ActionController::ParameterMissing do |e|
    render json: {error: e.message}, status: :bad_request
  end

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
    # `require` so a PATCH with no `notification` key returns 400 (ParameterMissing →
    # :bad_request) instead of a NoMethodError-on-nil 500. Mirrors FlagsController.
    params.require(:notification).permit(:read)
  end

  def notification
    @notification ||= Notification.find(params[:id])
  end
end
