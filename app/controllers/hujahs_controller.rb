class HujahsController < ApplicationController
  before_action :authenticate_user!, only: [:new, :create, :edit, :update, :destroy, :promote, :visibility_edit, :update_visibility]

  # The word the owner must type to confirm a destructive (tightening) visibility change.
  VISIBILITY_CONFIRM_WORD = "REMOVE"

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
    # Slice 2 (editable-hujah): a participant purged by a visibility tighten can no longer
    # see the live post — but they ARE entitled to their frozen archive. Route them there
    # instead of the generic not-authorized handling. skip_authorization satisfies
    # verify_authorized on this early-return branch (no authorize runs here).
    if !@hujah.visible_to?(current_user) && HujahArchiveParticipant.for(current_user, @hujah).exists?
      skip_authorization
      return redirect_to(hujah_archive_path(@hujah.slug))
    end
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

  def edit
    @hujah = Hujah.friendly.find(params[:slug])
    # HujahPolicy#edit? — owner + not-removed + within the edit window. A non-owner
    # or an expired window trips Pundit::NotAuthorizedError → the ApplicationController
    # rescue redirects back with "Not allowed." (never a bare 403).
    authorize @hujah
    @parent = @hujah.parent
    render :edit
  end

  def update
    @hujah = Hujah.friendly.find(params[:slug])
    # HujahPolicy#update? repeats body_editable?, so `authorize` IS the fail-closed
    # server-side re-check for a window that closed between the GET and this PATCH —
    # it raises → redirect back with an alert. No separate manual re-check needed
    # (a second identical guard would be unreachable dead code).
    authorize @hujah
    if @hujah.update(edit_params)
      # see_other so the browser re-GETs the show page after the PATCH. body_edited_at
      # is stamped by the model's before_update callback, not here.
      redirect_to hujah_path(@hujah.slug), notice: "Hoojah updated.", status: :see_other
    else
      @parent = @hujah.parent
      @hujah.restore_attributes([:slug]) # revert FriendlyId's in-memory slug regen so the re-rendered form PATCHes the persisted slug, not a never-saved one
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @hujah = Hujah.friendly.find(params[:slug])
    # Owner-only (HujahPolicy#destroy? = record.user_id == user.id, nil-safe). A
    # non-owner trips Pundit::NotAuthorizedError → the ApplicationController rescue
    # redirects back with an alert rather than a bare 403.
    authorize @hujah
    # Product rule lives on the model: Hujah#deletable? is false when the hoojah has
    # replies or a debate — other people's content that `dependent: :destroy` would
    # cascade away, so we refuse rather than silently delete it. `see_other` so the
    # browser re-GETs the redirect target after a DELETE.
    #
    # `with_lock` closes the check→destroy TOCTOU against a concurrent moderation or a
    # second delete. It does NOT fully close destroy-vs-reply (creating a reply never
    # locks the parent row) — that needs an ON DELETE RESTRICT FK on hujahs.parent_id,
    # tracked in HANDOVER's deferred backlog (a strong_migrations job on a populated table).
    @hujah.with_lock do
      unless @hujah.deletable?
        redirect_back fallback_location: hujah_path(@hujah.slug),
          alert: "You can't delete a hoojah that has responses or a debate.",
          status: :see_other
        return
      end
      @hujah.destroy
    end
    # Issue #38: return the user to the page they were on BEFORE they opened this
    # hoojah (captured at button-render time into `return_to`), not always the feed.
    # Re-validate the param HERE — defense in depth, never trust it blindly — and fall
    # back to root_path when it's absent/unsafe. `safe_return_path` also refuses the
    # deleted hoojah's own path (about to 404). The SAME destination drives both the
    # HTML redirect and the Turbo `visit`, so JS-on and JS-off agree.
    @destination = helpers.safe_return_path(params[:return_to], hujah_path(@hujah.slug)) || root_path
    # Delete is offered only on the show page — you are looking at the record you just
    # removed, so the browser must leave. A Turbo submission answers with a `visit`
    # stream (a `redirect_to` from a Stream-accepting form is fetched but not rendered
    # in this app — see the StreamAction in application.js); a plain HTML submit (JS off)
    # follows the `see_other` redirect natively.
    respond_to do |format|
      format.turbo_stream # destroy.turbo_stream.erb → <turbo-stream action="visit">
      format.html { redirect_to @destination, notice: "Hoojah deleted.", status: :see_other }
    end
  end

  def promote
    @hujah = Hujah.friendly.find(params[:slug])
    # Owner + child + not-removed via HujahPolicy#promote?. A non-owner / top-level target
    # trips Pundit::NotAuthorizedError → ApplicationController rescue redirects back with
    # an alert (not a bare 403).
    authorize @hujah, :promote?
    @hujah.promote!
    redirect_to hujah_path(@hujah.slug), notice: "Promoted to a standalone hoojah.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_back fallback_location: hujah_path(@hujah.slug),
      alert: "This hoojah can't be promoted (its body is too short for a top-level claim).",
      status: :see_other
  end

  # Slice 2: the change-visibility form. When `?to=` names a target the form doubles as
  # the confirmation screen; for a TIGHTENING target it renders the exact counts and any
  # entanglement blockers. change_visibility? is owner + top-level + not-removed.
  def visibility_edit
    @hujah = Hujah.friendly.find(params[:slug])
    authorize @hujah, :change_visibility?
    if params[:to].present? && Hujah.visibilities.key?(params[:to])
      @change = VisibilityChange.new(@hujah, to: params[:to])
      # blockers are PARTIAL-SELECT records (:id, :parent_id, :user_id) — no body/slug.
      # Reload them as FULL records so the view can render body/slug without raising
      # ActiveModel::MissingAttributeError. One query for the whole set.
      @blocker_args = Hujah.where(id: @change.blockers.map(&:id)) if @change.tightening?
    end
  end

  # Slice 2: apply a visibility change. Loosening/no-op update the column directly;
  # tightening is destructive and gated: entanglement blockers refuse the change, and the
  # owner must type VISIBILITY_CONFIRM_WORD. VisibilityChange#apply! re-derives the
  # affected set and re-checks entanglement UNDER a row lock, so the server never trusts
  # the client and fails closed on anything that changed since the confirmation GET.
  def update_visibility
    @hujah = Hujah.friendly.find(params[:slug])
    authorize @hujah, :change_visibility?
    to = params.require(:hujah).permit(:visibility)[:visibility]

    unless Hujah.visibilities.key?(to)
      return redirect_to(visibility_hujah_path(@hujah.slug), alert: "Unknown visibility.", status: :see_other)
    end

    change = VisibilityChange.new(@hujah, to: to)

    if change.no_op?
      redirect_to hujah_path(@hujah.slug), notice: "Visibility unchanged.", status: :see_other
    elsif change.loosening?
      @hujah.update!(visibility: to)
      redirect_to hujah_path(@hujah.slug), notice: "Visibility updated.", status: :see_other
    else
      if change.blockers.any?
        return redirect_to(visibility_hujah_path(@hujah.slug, to: to),
          alert: "Resolve the entangled arguments before tightening.", status: :see_other)
      end
      if params[:confirm] != VISIBILITY_CONFIRM_WORD
        return redirect_to(visibility_hujah_path(@hujah.slug, to: to),
          alert: "Type #{VISIBILITY_CONFIRM_WORD} to confirm the permanent removal.", status: :see_other)
      end
      begin
        change.apply!
        redirect_to hujah_path(@hujah.slug),
          notice: "Visibility tightened. Affected participation was permanently removed.",
          status: :see_other
      rescue VisibilityChange::Blocked
        redirect_to(visibility_hujah_path(@hujah.slug, to: to),
          alert: "An argument became entangled — the change was blocked.", status: :see_other)
      end
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
  #
  # Slice 3: agree/neutral/disagree_label ride the create path only. They are
  # attr_readonly on the model (immutable after create) and coerced to nil there when
  # the author is not eligible (top-level + can_customize_stances?), so permitting them
  # here is safe — the gate is enforced in the model, not by withholding the param.
  def compose_params
    params.require(:hujah).permit(:body, :parent_id, :vote, :visibility, :allow_debates,
      :agree_label, :neutral_label, :disagree_label)
  end

  # Slice 1 body edit: permit ONLY the body — never stance/visibility/custom labels
  # (those are other slices, and stance/visibility are immutable here). allow_debates
  # rides the same form but is a TOP-LEVEL-only control (replies have no such toggle),
  # so it is permitted only when this is a top-level claim.
  def edit_params
    permitted = [:body]
    permitted << :allow_debates if @hujah.parent_id.nil?
    params.require(:hujah).permit(*permitted)
  end
end
