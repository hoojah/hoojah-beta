class DebateTurnsController < ApplicationController
  before_action :authenticate_user!

  # A denied turn post is a hard 403 in every format — the C1 security boundary
  # (only the current_turn_user may post) must never soften to a redirect.
  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

  # Post the current user's turn. Strong params permit ONLY :body (never user_id
  # or position — those are derived by the model).
  #
  # SECURITY-CRITICAL (C1): authorize a DebateTurn INSTANCE so Pundit resolves
  # DebateTurnPolicy#create? (turn-scoped — only `current_turn_user` may post).
  # Authorizing @debate would resolve DebatePolicy#create? = user.present?, which
  # would let ANY signed-in user post ANY turn (full bypass).
  def create
    @debate = Debate.friendly.find(params[:slug])
    authorize @debate.turns.new(user: current_user), :create?

    if @debate.post_turn(by: current_user, body: turn_params[:body])
      @turn = @debate.turns.order(:position).last
      respond_to do |format|
        format.turbo_stream # create.turbo_stream.erb
        format.html { redirect_to debate_path(@debate.slug), status: :see_other }
      end
    else
      head :unprocessable_content
    end
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_content
  end

  private

  def turn_params = params.permit(:body)

  def render_forbidden = head :forbidden
end
