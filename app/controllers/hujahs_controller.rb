class HujahsController < ApplicationController
  before_action :authenticate_user!, only: [:new, :create]

  def index
    skip_authorization
    @pagy, @hujahs = pagy(
      :countless,
      Hujah.where(parent_id: nil).includes(:user).order(updated_at: :desc)
    )

    respond_to do |format|
      format.html
      format.turbo_stream # index.turbo_stream.erb (load-more append)
    end
  end

  def show
    skip_authorization
    @hujah = Hujah.friendly.find(params[:slug])
    @children = @hujah.children.includes(:user).order(updated_at: :desc)
  end

  def new
    skip_authorization
    @parent = params[:slug] && Hujah.friendly.find(params[:slug])
    @hujah = Hujah.new
  end

  def create
    authorize Hujah
    # A spoofed/missing parent_id must not nil-deref: Hujah.find raising
    # RecordNotFound resolves to 404 (the app runs show_exceptions=:none in
    # test, so rescue here to return the status the request spec asserts).
    @parent = params.dig(:hujah, :parent_id).presence && Hujah.find(params[:hujah][:parent_id])
    @hujah = current_user.hujahs.new(compose_params)
    if @hujah.save
      redirect_to hujah_path(@hujah.slug), status: :see_other
    else
      @parent ||= nil
      render :new, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  # Body is stored RAW (no <br> hack); it renders via the `format_body` helper.
  # A missing/spoofed parent_id makes `Hujah.find` raise RecordNotFound → 404,
  # which the request spec accepts.
  def compose_params
    params.require(:hujah).permit(:body, :parent_id, :vote)
  end
end
