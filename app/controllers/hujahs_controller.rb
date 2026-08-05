class HujahsController < ApplicationController
  before_action :authenticate_user!, only: [:new, :create]

  def index
    skip_authorization
    # Anonymous `?filter=following` must fall back to the global feed (no 500 on
    # current_user being nil), so the branch also requires user_signed_in?.
    base = if params[:filter] == "following" && user_signed_in?
      Hujah.timeline_for(current_user).includes(:user).order(updated_at: :desc)
    else
      global = Hujah.where(parent_id: nil).includes(:user).order(updated_at: :desc)
      # Slice 7b (Gate 1): the global feed NEVER shows a private author — UNCONDITIONAL
      # (anonymous too). A private user's content lives on their gated profile and in
      # their accepted followers' Following feed, never the public feed.
      global = global.joins(:user).where(users: {private: false})
      # Slice 7: signed-in viewers never see a hidden (blocked/blocked-by) author's
      # top-level hoojahs; anonymous is deliberately unfiltered.
      global = global.where.not(user_id: current_user.hidden_user_ids) if user_signed_in?
      global
    end
    @pagy, @hujahs = pagy(:countless, base)

    respond_to do |format|
      format.html
      format.turbo_stream # index.turbo_stream.erb (load-more append)
    end
  end

  def show
    @hujah = Hujah.friendly.find(params[:slug])
    # Slice 7b (Gate 5): a private author's hoojah is viewable only by themselves and
    # accepted followers. HujahPolicy#show? = record.user.visible_to?(user) (nil-safe;
    # anonymous → the ApplicationController Pundit rescue redirects, not a bare 403).
    authorize @hujah
    @children = @hujah.children.includes(:user).order(updated_at: :desc)
    # Slice 7: hide replies from a hidden (blocked/blocked-by) author (incl. pre-block
    # replies; new ones are rejected at create). Signed-in only — anonymous unfiltered.
    @children = @children.where.not(user_id: current_user.hidden_user_ids) if user_signed_in?
    # Slice 7b (Gate 6): hide a PRIVATE replier's reply from anyone who can't see them —
    # UNCONDITIONAL per-viewer SQL predicate (no N+1). Accepted followers (+ self) see
    # private replies via their following_ids; strangers and anonymous do not.
    visible_ids = user_signed_in? ? current_user.following_ids + [current_user.id] : []
    @children = @children.joins(:user).where("users.private = false OR hujahs.user_id IN (?)", visible_ids)
    # Debates lens (Slice 4). policy_scope hides others' active/pending/declined
    # debates but shows concluded ones publicly. This is NOT a separate route —
    # it renders inline on the hoojah page. policy_scope does not count toward
    # verify_authorized (skip_authorization above still satisfies it).
    @debates = policy_scope(@hujah.debates)
  end

  def new
    skip_authorization
    @parent = params[:slug] && Hujah.friendly.find(params[:slug])
    @hujah = Hujah.new
  end

  def create
    # A spoofed/missing parent_id must not nil-deref: Hujah.find raising
    # RecordNotFound resolves to 404 (the app runs show_exceptions=:none in
    # test, so rescue here to return the status the request spec asserts).
    @parent = params.dig(:hujah, :parent_id).presence && Hujah.find(params[:hujah][:parent_id])
    # Build the instance (with its parent_id) BEFORE authorizing so HujahPolicy#create?
    # can read record.parent.user_id and reject a reply to a hidden pair (Slice 7).
    @hujah = current_user.hujahs.new(compose_params)
    authorize @hujah
    if @hujah.save
      redirect_to hujah_path(@hujah.slug), status: :see_other
    else
      @parent ||= nil
      render :new, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    # The parent lookup raised before `authorize` ran — satisfy verify_authorized.
    skip_authorization
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
