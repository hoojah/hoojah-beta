class Api::V1::VotesController < Api::V1::BaseController
  before_action :authenticate_user!, only: :create

  def create
    hujah.cast_vote(by: current_user, choice: vote_params[:vote])
    render json: { message: 'ok' }
  end

  private

  def vote_params
    params.permit(:vote, :hujah_id)
  end

  def hujah
    @hujah ||= Hujah.find(params[:hujah_id])
  end
end
