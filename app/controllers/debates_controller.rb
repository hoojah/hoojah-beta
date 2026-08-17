class DebatesController < ApplicationController
  before_action :authenticate_user!, except: [:show]
  before_action :set_debate, only: [:show, :accept, :decline, :conclude, :extend_rounds]

  # A Pundit denial on a debate endpoint is a hard 403 in every format (the
  # global handler redirects HTML — here the denial IS the security boundary, so
  # a non-participant peeking at an active debate, or a non-current-turn user
  # posting, must get a flat 403, not a friendly redirect).
  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

  # accept!/decline!/conclude!/extend_rounds! all go through update!, which
  # revalidates the WHOLE row, not just the column being changed. Each action's own
  # guard already refuses the invalid transition (extendable_by? at the MAX_ROUNDS
  # ceiling, the policy for the rest), so what is left is a row that went invalid by
  # some other route — that must be a 422, never a 500.
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable

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
    # The argument must be a direct child of the URL's hoojah, else it is forged, so
    # scope the lookup by that constraint rather than re-checking it afterwards
    # (the same move as `current_user.challenged_debates` below). Both bad-input
    # cases — an unknown id and a real argument on another hoojah — then converge on
    # one 422; an unscoped `Hujah.find` would raise RecordNotFound for the first and
    # turn a turbo_stream POST into a 404 HTML page. This is input validation, not
    # authorization — skip_authorization satisfies verify_authorized on the early-out.
    argument = @hujah.children.find_by(id: challenge_params[:argument_id])
    unless argument
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
  end

  def decline
    authorize @debate, :decline?
    @debate.decline!(by: current_user)
    render_status
  end

  def conclude
    authorize @debate, :conclude?
    @debate.conclude!(by: current_user)
    render_status
  end

  # Extend the debate by one round (Slice 9). Named `extend_rounds`, not `extend`,
  # because `extend` would shadow Object#extend on the controller instance.
  #
  # The 403/422 split is the point: DebatePolicy#extend? is coarse (participant on
  # an active debate), so a legitimate participant is AUTHORIZED to ask and a
  # mistimed ask — outside the closing-round boundary, or at the MAX_ROUNDS
  # ceiling — falls through extend_rounds!'s own locked re-check to 422. Only a
  # non-participant (or a non-active debate) gets 403.
  def extend_rounds
    authorize @debate, :extend?
    if @debate.extend_rounds!(by: current_user)
      # No :json branch on purpose — an unknown format raises UnknownFormat (406),
      # matching render_status. This endpoint is Turbo-only by design.
      respond_to do |format|
        format.turbo_stream # extend_rounds.turbo_stream.erb
        format.html { redirect_to debate_path(@debate.slug), status: :see_other }
      end
    else
      head :unprocessable_content
    end
  end

  private

  def set_debate = @debate = Debate.friendly.find(params[:slug])

  def render_forbidden = head :forbidden

  def render_unprocessable = head :unprocessable_content

  def challenge_params = params.permit(:argument_id, :challenger_stance)

  def render_status
    respond_to do |format|
      format.turbo_stream { render :status }
      format.html { redirect_to debate_path(@debate.slug), status: :see_other }
    end
  end
end
