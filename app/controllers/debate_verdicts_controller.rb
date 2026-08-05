class DebateVerdictsController < ApplicationController
  before_action :authenticate_user!

  # A denied verdict is a hard 403 in every format — the visibility/participant
  # boundary must never soften to a redirect (matching the sibling debate
  # controllers).
  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

  # Cast the current user's verdict on a concluded debate.
  #
  # SECURITY-CRITICAL (C1): authorize a DebateVerdict INSTANCE so Pundit resolves
  # DebateVerdictPolicy#create? (concluded + non-participant + show? visibility).
  # Authorizing @debate would resolve the wrong policy.
  def create
    @debate = Debate.friendly.find(params[:slug])
    authorize @debate.debate_verdicts.new(user: current_user, choice: verdict_params[:choice]), :create?

    if @debate.cast_verdict(by: current_user, choice: verdict_params[:choice])
      respond_to do |format|
        format.turbo_stream # create.turbo_stream.erb
        format.html { redirect_to debate_path(@debate.slug), status: :see_other }
      end
    else
      head :unprocessable_content
    end
  rescue ArgumentError
    # An unknown `choice` raises when the enum is assigned on .new (before
    # authorize); treat it as invalid input, not a 500. skip_authorization
    # satisfies verify_authorized on this early-out.
    skip_authorization
    head :unprocessable_content
  end

  private

  def verdict_params = params.permit(:choice)

  def render_forbidden = head :forbidden
end
