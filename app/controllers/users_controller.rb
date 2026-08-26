class UsersController < ApplicationController
  before_action :authenticate_user!, only: [:edit, :update]
  before_action :set_user

  def show
    skip_authorization
    # Slice 7b (Gate 4): a private author's hoojah list is loaded ONLY for a viewer who
    # may see it (self + accepted followers). The view renders a gated header (avatar,
    # name, @handle, "This account is private", follow button, follower/following
    # counts) with no hoojah list / headline / location / link / badges otherwise.
    @gated = !@user.visible_to?(current_user)
    unless @gated
      # Hoojah 2026 (redesign Phase 4, Task 4.5): the profile's Hoojahs / Responses /
      # Debates count tabs. Counts are plain association counts — no new columns, no
      # query object — and only the ACTIVE tab's list is loaded.
      @active_tab = params[:tab].in?(%w[hoojahs responses debates]) ? params[:tab] : "hoojahs"
      # Moderation: E7 sweep — profile counters exclude removed content (hidden even
      # from its author, so their own counts must not include it).
      @hoojahs_count = @user.hujahs.not_removed.where(parent_id: nil).count
      @responses_count = @user.hujahs.not_removed.where.not(parent_id: nil).count
      @debates_count = @user.challenged_debates.count + @user.defended_debates.count
      @list = profile_tab_list(@active_tab)
      # Hoojah 2026 (redesign Phase 4, Task 4.4): the profile's live-debate card.
      # LEAK PREVENTION carried forward from Phase 1.7-fix — `Hujah#active_debate`
      # is per-CLAIM and not usable here; the profile needs the OWNER's own active
      # debate as a participant (challenger or opponent), computed directly.
      @active_debate = owner_visible_active_debate
    end
  end

  # Hovercard body (Slice B). layout:false partial fetched by hovercard_controller.js on
  # hover. Same privacy gate as #show — `visible_to?` decides Standard vs the gated minimal
  # whitelist — so the two surfaces cannot drift. skip_authorization (else verify_authorized
  # 500s); no authenticate_user!, so guests may view a public card.
  def card
    skip_authorization
    @gated = !@user.visible_to?(current_user)
    render "users/card", layout: false
  end

  # Follower / following lists. Public by default; Slice 7b (Gate 7) gates the lists of
  # a private account behind visible_to? (a stranger must not enumerate them).
  # skip_authorization (else verify_authorized 500s).
  def followers
    skip_authorization
    return redirect_to profile_path(@user.username) unless @user.visible_to?(current_user)
    @users = @user.followers.with_attached_avatar.order(:username)
  end

  def following
    skip_authorization
    return redirect_to profile_path(@user.username) unless @user.visible_to?(current_user)
    @users = @user.following.with_attached_avatar.order(:username)
  end

  def edit
    authorize @user
  end

  def update
    authorize @user
    # Slice 7b (Phase 3.2) / Slice C (gap 5): when a user flips private→public, accept
    # every pending follow request. Captured BEFORE the update so the transition is
    # detectable. The original bulk `update_all` was a silent write
    # that skipped ALL side effects — it left requesters unaware they may now follow (no
    # follow_accepted), the target unnotified/unbadged (no new_follower / first_follower),
    # the stale request cards undismissed, and (since gap 8) the accepted-only counter
    # caches unmoved. Routing each row through Follow#update! fires all of those from the
    # one place they live. AcceptPendingFollowsJob does the per-row work.
    was_private = @user.private?
    if @user.update(user_params)
      if was_private && !@user.private?
        # Small sets accept inline (the flip's effects are immediately visible in the
        # response cycle); large sets go to the job so the request doesn't stall on N
        # notification writes.
        if @user.passive_follows.pending.count <= AcceptPendingFollowsJob::INLINE_THRESHOLD
          AcceptPendingFollowsJob.perform_now(@user)
        else
          AcceptPendingFollowsJob.perform_later(@user)
        end
      end
      respond_to do |format|
        format.turbo_stream # update.turbo_stream.erb — refresh header + close_dialog
        format.html { redirect_to profile_path(@user.username), status: :see_other }
      end
    else
      # Re-render the form as HTML for every request format (there is no
      # edit.turbo_stream variant) so a failed Turbo-Stream submit still 422s.
      render :edit, status: :unprocessable_content, formats: [:html]
    end
  end

  private

  # Look up by username (the public identifier). Missing → 404.
  def set_user
    @user = User.find_by!(username: params[:username])
  end

  # Email stays API-only (the HTML edit form omits it, matching the legacy SPA).
  def user_params
    params.require(:user).permit(:full_name, :username, :location, :link, :headline, :photo, :private, :avatar)
  end

  # Hoojah 2026 (redesign Phase 4, Task 4.5). The list for whichever tab is active.
  #
  # Hoojahs: the SAME per-post-visibility scoping the profile always applied
  # (Slice 7b / 2026), narrowed to top-level (`parent_id: nil`) — Responses below is
  # what used to be mixed in here unfiltered.
  #
  # Responses: `Hujah#visible_to?` for a REPLY recurses through `parent.visible_to?`,
  # which is not expressible as one SQL predicate (see `Hujah.visible_to`'s own
  # comment) — so a page of the owner's replies is loaded and then filtered in Ruby.
  # This is the LEAK surface: a reply the owner posted under someone else's
  # followers_only/private_only claim must not surface to a viewer who cannot see
  # that parent, even though the reply's own author (the profile owner) is visible.
  #
  # Debates: routed through `policy_scope`/`DebatePolicy::Scope`, never a raw list —
  # a stranger must not learn of a debate whose OTHER participant is private/blocked
  # to them. `hujahs_controller.rb`'s Debates lens uses the same policy_scope call
  # unpaginated; this mirrors that rather than inventing a query object.
  def profile_tab_list(tab)
    case tab
    when "responses"
      @pagy, replies = pagy(:countless,
        @user.hujahs.where.not(parent_id: nil).includes(user: {avatar_attachment: :blob}, parent: {user: {avatar_attachment: :blob}}).order(updated_at: :desc))
      replies.select { |reply| reply.visible_to?(current_user) }
    when "debates"
      base = Debate.where(challenger_id: @user.id).or(Debate.where(opponent_id: @user.id))
        .includes(:challenger, :opponent, :hujah).order(created_at: :desc)
      policy_scope(base)
    else
      # Slice 11: the per-post-visibility profile predicate now lives on the model
      # (User#visible_hujahs_for) so the HTML "Hoojahs" tab and the API UserSerializer
      # share ONE gate and cannot drift.
      @user.visible_hujahs_for(current_user)
    end
  end

  # The profile owner's own active debate (they are challenger OR opponent),
  # gated by the SAME predicate as `HujahsController#debate_teaser_visible?` —
  # a private/blocked co-debater's handle must never appear on the owner's
  # profile to a viewer who couldn't otherwise see them. Returns nil both when
  # there is no active debate and when the leak filter excludes it, so the view
  # can render the card unconditionally on `@active_debate.present?`.
  def owner_visible_active_debate
    debate = Debate.active
      .where("challenger_id = :id OR opponent_id = :id", id: @user.id)
      .includes(:challenger, :opponent, :hujah)
      .first
    return nil unless debate
    return nil unless debate.challenger.visible_to?(current_user) && debate.opponent.visible_to?(current_user)
    return nil if current_user && (current_user.hidden_user_ids & [debate.challenger_id, debate.opponent_id]).any?
    # Moderation (C-1): the card quotes the claim body, and this action has no
    # authenticate_user! — a removed claim is staff-only, so gate it per-record like
    # every other content surface (debates/show + _verdict + _debate_pending).
    return nil unless debate.hujah.visible_to?(current_user)
    debate
  end
end
