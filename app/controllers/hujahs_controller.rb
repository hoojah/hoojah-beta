class HujahsController < ApplicationController
  def index
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
    @hujah = Hujah.friendly.find(params[:slug])
    @children = @hujah.children.includes(:user).order(updated_at: :desc)
  end
end
