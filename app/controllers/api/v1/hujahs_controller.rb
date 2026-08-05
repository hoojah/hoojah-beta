class Api::V1::HujahsController < Api::V1::BaseController
  before_action :authenticate_user!, only: :destroy

  def index
    skip_authorization
    hujahs = Hujah.all.order(updated_at: :desc)
    serialized_hujahs = HujahSerializer.new(hujahs, params: {logged_in: user_signed_in?, current_user_id: current_user&.id}).serializable_hash
    render json: serialized_hujahs
  end

  def create
    # Authorize the built instance (not the Hujah class) so the shared HujahPolicy#create?
    # can read parent_id — same instance-authorize shape as the HTML controller (Slice 7).
    @hujah = current_user.hujahs.new(hujah_params)
    authorize @hujah
    if @hujah.save
      render json: @hujah
    else
      render json: @hujah.errors
    end
  end

  def show
    skip_authorization
    if hujah

      serialized_hujah = HujahSerializer.new(hujah, params: {logged_in: user_signed_in?, current_user_id: current_user&.id}).serializable_hash

      render json: serialized_hujah
    end
  end

  def destroy
    authorize hujah
    hujah.destroy
    render json: {message: "Hoojah deleted!"}
  end

  def new
    skip_authorization
  end

  private

  def hujah_params
    params.permit(:body, :parent_id, :vote)
  end

  def hujah
    @hujah ||= Hujah.friendly.find(params[:slug])
  end
end
