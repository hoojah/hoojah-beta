# Favourites (2026): the parent claim's author stars/unstars a reply to their claim.
# `:slug` is the REPLY's. Both actions redirect back to the parent's thread (see_other so
# the browser re-GETs after POST/DELETE); that works identically with Turbo on or off.
class FavouritesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_reply

  def create
    @reply.favourite!
    redirect_to thread_path, status: :see_other
  rescue Hujah::FavouriteLimitReached
    redirect_to thread_path, status: :see_other,
      alert: "You can favourite up to #{Hujah::FAVOURITES_PER_STANCE} #{Hujah::STANCES[@reply.vote]} responses. Unfavourite one first."
  end

  def destroy
    @reply.unfavourite!
    redirect_to thread_path, status: :see_other
  end

  private

  def set_reply
    @reply = Hujah.friendly.find(params[:slug])
    # HujahPolicy#favourite? — parent author only. A non-owner trips
    # Pundit::NotAuthorizedError → the ApplicationController rescue redirects back.
    authorize @reply, :favourite?
  end

  def thread_path = hujah_path(@reply.parent.slug)
end
