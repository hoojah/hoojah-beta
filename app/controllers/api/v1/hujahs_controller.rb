class Api::V1::HujahsController < Api::V1::BaseController
  before_action :authenticate_user!, only: :destroy

  def index
    skip_authorization
    # Slice 7b (Gate 11, A-1): private authors are a hard boundary — never expose them
    # through the JSON index (full follower-aware parity is deferred to Project 3).
    # Per-post visibility (2026): the public API index is a hard boundary —
    # visible_public only (follower-aware parity is deferred to Project 3).
    hujahs = Hujah.joins(:user).where(users: {private: false})
      .where(visibility: :visible_public).order(updated_at: :desc)
    serialized_hujahs = HujahSerializer.new(hujahs, params: {logged_in: user_signed_in?, current_user_id: current_user&.id, current_user: current_user}).serializable_hash
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
    # Slice 7b (Gate 11, A-1): deny a private author's hoojah to anyone who can't see
    # them — the content the feature hides must not be one guessable URL away.
    if hujah&.visible_to?(current_user)
      serialized_hujah = HujahSerializer.new(hujah, params: {logged_in: user_signed_in?, current_user_id: current_user&.id, current_user: current_user}).serializable_hash

      render json: serialized_hujah
    else
      head :not_found
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
