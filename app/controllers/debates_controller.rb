class DebatesController < ApplicationController
  before_action :authenticate_user!, except: [:show]
  before_action :set_debate, only: [:show, :accept, :decline, :conclude]

  # A Pundit denial on a debate endpoint is a hard 403 in every format (the
  # global handler redirects HTML — here the denial IS the security boundary, so
  # a non-participant peeking at an active debate, or a non-current-turn user
  # posting, must get a flat 403, not a friendly redirect).
  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

  # Public, read-only transcript. `authorize @debate` resolves DebatePolicy#show?
  # (concluded → anyone incl. logged-out; active → participants only). Turns +
  # participants eager-loaded for the view.
  def show
    authorize @debate
    @turns = @debate.turns.includes(:user).order(:position)
  end

  # Challenge escalated from an argument on THIS hoojah. The actor is always the
  # current_user (challenged_debates) — opponent/stances are DERIVED from the
  # argument, never accepted from params (only :argument_id + :challenger_stance).
  def create
    @hujah = Hujah.friendly.find(params[:slug])
    argument = Hujah.find(challenge_params[:argument_id])
    # The argument must be a direct child of the URL's hoojah, else it is forged.
    # This is input validation, not authorization — skip_authorization satisfies
    # verify_authorized on the early-out.
    unless argument.parent_id == @hujah.id
      skip_authorization
      return head :unprocessable_content
    end

    @argument = argument
    @debate = current_user.challenged_debates.new(
      hujah: @hujah,
      opponent: argument.user,
      opponent_stance: argument.vote,
      challenger_stance: challenge_params[:challenger_stance]
    )
    authorize @debate, :create?

    if @debate.save
      respond_to do |format|
        format.turbo_stream # create.turbo_stream.erb
        format.html { redirect_to debate_path(@debate.slug), status: :see_other }
      end
    else
      head :unprocessable_content
    end
  rescue ActiveRecord::RecordNotUnique
    # A concurrent duplicate live challenge races past the partial-unique index —
    # swallow it so the challenge stays an idempotent no-op instead of a 500.
    head :unprocessable_content
  end

  def accept
    authorize @debate, :accept?
    @debate.accept!(by: current_user)
    render_status
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_content
  end

  def decline
    authorize @debate, :decline?
    @debate.decline!(by: current_user)
    render_status
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_content
  end

  def conclude
    authorize @debate, :conclude?
    @debate.conclude!(by: current_user)
    render_status
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_content
  end

  private

  def set_debate = @debate = Debate.friendly.find(params[:slug])

  def render_forbidden = head :forbidden

  def challenge_params = params.permit(:argument_id, :challenger_stance)

  def render_status
    respond_to do |format|
      format.turbo_stream { render :status }
      format.html { redirect_to debate_path(@debate.slug), status: :see_other }
    end
  end
end
