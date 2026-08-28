class HujahsController < ApplicationController
  before_action :authenticate_user!, only: [:new, :create, :destroy]

  def index
    skip_authorization
    # Anonymous `?filter=following` must fall back to the global feed (no 500 on
    # current_user being nil), so the branch also requires user_signed_in?.
    base = if params[:filter] == "following" && user_signed_in?
      # Per-post visibility (2026): followers may see visible_public + followers_only
      # from people they follow, PLUS the viewer's own private_only claims (don't
      # over-hide — timeline_for already includes current_user.id).
      Hujah.timeline_for(current_user)
        .where("hujahs.visibility IN (0, 1) OR hujahs.user_id = ?", current_user.id)
        .includes(user: {avatar_attachment: :blob}).order(updated_at: :desc)
    else
      # Moderation: E1 sweep — the global/anonymous feed never shows removed claims.
      global = Hujah.not_removed.where(parent_id: nil).includes(user: {avatar_attachment: :blob}).order(updated_at: :desc)
      # Slice 7b (Gate 1): the global feed NEVER shows a private author — UNCONDITIONAL
      # (anonymous too). A private user's content lives on their gated profile and in
      # their accepted followers' Following feed, never the public feed.
      global = global.joins(:user).where(users: {private: false})
      # Per-post visibility (2026): the global/anonymous feed shows only visible_public.
      global = global.where(visibility: :visible_public)
      # Slice 7: signed-in viewers never see a hidden (blocked/blocked-by) author's
      # top-level hoojahs; anonymous is deliberately unfiltered.
      global = global.where.not(user_id: current_user.hidden_user_ids) if user_signed_in?
      global
    end
    @pagy, @hujahs = pagy(:countless, base)
    preload_active_debates(@hujahs)

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
    # Slice 11: the Slice-7/7b reply-visibility predicate now lives on the model
    # (Hujah#visible_children_for) so the HTML thread and the JSON API serializer
    # share ONE gate and cannot drift. Same query, same order, no N+1.
    @children = @hujah.visible_children_for(current_user)
    # Debates lens (Slice 4). policy_scope hides others' active/pending/declined
    # debates but shows concluded ones publicly. This is NOT a separate route —
    # it renders inline on the hoojah page. policy_scope does not count toward
    # verify_authorized (skip_authorization above still satisfies it).
    @debates = policy_scope(@hujah.debates)
  end

  def new
    # SECURITY: the respond composer renders the parent claim's body via _parent_card,
    # so a parent must be authorized for #show? here — otherwise a non-follower reads a
    # followers_only/private_only claim's body by guessing its slug. Top-level compose
    # has no parent, so it stays skip_authorization to satisfy verify_authorized.
    @parent = params[:slug] && Hujah.friendly.find(params[:slug])
    @parent ? authorize(@parent, :show?) : skip_authorization
    @hujah = Hujah.new
    @suggested_tags = Hashtag.order(hujahs_count: :desc).limit(6) # trending, for chips
  end

  def create
    # A spoofed/missing parent_id must not nil-deref: Hujah.find raising
    # RecordNotFound propagates (the parent lookup happens before `authorize`
    # runs, so verify_authorized never fires for this action) straight to the
    # branded 404 (config.exceptions_app = routes) instead of a blank body.
    @parent = params.dig(:hujah, :parent_id).presence && Hujah.find(params[:hujah][:parent_id])
    # Build the instance (with its parent_id) BEFORE authorizing so HujahPolicy#create?
    # can read record.parent.user_id and reject a reply to a hidden pair (Slice 7).
    @hujah = current_user.hujahs.new(compose_params)
    authorize @hujah
    if @hujah.save
      respond_to do |format|
        # The inline feed composer is a Turbo form and gets a stream that prepends the
        # new card to #hujah-feed (create.turbo_stream.erb). The full-page composer form
        # submits with turbo:false, so it lands here as HTML and redirects to the hoojah.
        format.turbo_stream
        format.html { redirect_to hujah_path(@hujah.slug), status: :see_other }
      end
    else
      @parent ||= nil
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    @hujah = Hujah.friendly.find(params[:slug])
    # Owner-only (HujahPolicy#destroy? = record.user_id == user.id, nil-safe). A
    # non-owner trips Pundit::NotAuthorizedError → the ApplicationController rescue
    # redirects back with an alert rather than a bare 403.
    authorize @hujah
    # Product rule: a HARD destroy is only offered on a "leaf" claim. A hoojah with
    # replies or debates carries other people's content (child arguments, a whole
    # debate transcript) that `dependent: :destroy` would cascade away — refuse
    # instead of silently deleting it. `see_other` so the browser re-GETs the
    # redirect target after a DELETE.
    if @hujah.children.any? || @hujah.debates.any?
      redirect_back fallback_location: hujah_path(@hujah.slug),
        alert: "You can't delete a hoojah that has responses or a debate.",
        status: :see_other
      return
    end
    @hujah.destroy
    # Delete is offered only on the show page — you are looking at the record you just
    # removed, so the browser must leave. A Turbo submission answers with a `visit`
    # stream (a `redirect_to` from a Stream-accepting form is fetched but not rendered
    # in this app — see the StreamAction in application.js); a plain HTML submit (JS off)
    # follows the `see_other` redirect natively.
    respond_to do |format|
      format.turbo_stream # destroy.turbo_stream.erb → <turbo-stream action="visit">
      format.html { redirect_to root_path, notice: "Hoojah deleted.", status: :see_other }
    end
  end

  private

  # Phase 1.5 (2026): the feed's live-debate strip needs to know, per top-level
  # hujah, whether it has an active debate — WITHOUT an N+1. One bulk query for
  # every id on the page, indexed by hujah_id, then assigned onto each record via
  # Hujah#preloaded_active_debate= so #active_debate reads it for free. `@hujahs`
  # may still be an unloaded pagy relation here; `.each` after `.map(&:id)` reuses
  # the same loaded records rather than re-querying.
  #
  # Phase 1.7-fix (security): an ACTIVE debate is participant-only under
  # DebatePolicy#show?, but the strip (hujahs/_live_debate_strip) and the
  # swords/"Jump in" footer (hujahs/_hujah_card) render straight off this
  # preload for EVERY feed viewer. Left unfiltered that broadcasts a private
  # participant's handle + live activity to anonymous/stranger viewers, and a
  # blocked participant's handle to a viewer who blocked them. So a debate is
  # kept here only when BOTH participants are visible to the viewer (mirrors
  # User#visible_to?, same shape as DebatePolicy::Scope#resolve) AND neither is
  # in the viewer's `hidden_user_ids`. A filtered-out hujah gets an EXPLICIT nil
  # write (not simply "no entry") — Hujah#active_debate's `defined?` check
  # trusts an explicit nil from the preload and does not fall back to a live
  # per-record query, which would silently re-leak the debate it was just
  # filtered out for. This is a page-sized Ruby filter, not SQL: challenger/
  # opponent are already `includes`-loaded, so `visible_to?` costs at most one
  # `accepted_follower?` query per PRIVATE participant on the page, not per row.
  def preload_active_debates(hujahs)
    ids = hujahs.map(&:id)
    active_by_hujah_id = Debate.active.where(hujah_id: ids).includes(:challenger, :opponent).index_by(&:hujah_id)
    hujahs.each do |h|
      debate = active_by_hujah_id[h.id]
      debate = nil if debate && !debate_teaser_visible?(debate)
      h.preloaded_active_debate = debate
    end
  end

  def debate_teaser_visible?(debate)
    debate.challenger.visible_to?(current_user) &&
      debate.opponent.visible_to?(current_user) &&
      (current_user.nil? || (current_user.hidden_user_ids & [debate.challenger_id, debate.opponent_id]).empty?)
  end

  # Body is stored RAW (no <br> hack); it renders via the `format_body` helper.
  # A missing/spoofed parent_id makes `Hujah.find` raise RecordNotFound → 404,
  # which the request spec accepts.
  def compose_params
    params.require(:hujah).permit(:body, :parent_id, :vote, :visibility, :allow_debates)
  end
end
