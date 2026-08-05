class VotesController < ApplicationController
  before_action :authenticate_user!

  def create
    @hujah = Hujah.friendly.find(params[:slug])
    authorize @hujah, :vote?
    @hujah.cast_vote(by: current_user, choice: params[:vote])

    respond_to do |format|
      format.turbo_stream # create.turbo_stream.erb — replaces the _vote_bars widget in place
      format.html { redirect_to hujah_path(@hujah.slug) }
    end
  end
end
