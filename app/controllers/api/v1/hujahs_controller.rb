class Api::V1::HujahsController < Api::V1::BaseController
  before_action :authenticate_user!, only: :destroy
  before_action :require_owner!, only: :destroy

  def index
    hujahs = Hujah.all.order(updated_at: :desc)
    serialized_hujahs = HujahSerializer.new(hujahs, params: {logged_in: user_signed_in?, current_user_id: current_user&.id}).serializable_hash
    render json: serialized_hujahs
  end

  def create
    hujah = current_user.hujahs.create(hujah_params)
    if hujah
      if hujah.has_parent?
        Notification.create!(user_id: hujah.parent.user.id, category: 3, hujah_id: hujah.parent.id, subject_user_id: current_user.id)
      end
      render json: hujah
    else
      render json: hujah.errors
    end
  end

  def show
    if hujah

      serialized_hujah = HujahSerializer.new(hujah, params: {logged_in: user_signed_in?, current_user_id: current_user&.id}).serializable_hash

      render json: serialized_hujah
    end
  end

  def destroy
    hujah.destroy
    render json: {message: "Hoojah deleted!"}
  end

  def new
  end

  private

  def require_owner!
    head :forbidden unless hujah&.user_id == current_user.id
  end

  def hujah_params
    params.permit(:body, :parent_id, :vote)
  end

  def hujah
    @hujah ||= Hujah.friendly.find(params[:slug])
  end
end
