class Hujah < ApplicationRecord
  belongs_to :user
  has_many :votes, dependent: :destroy
  has_many :flags, dependent: :destroy
  has_many :children, class_name: "Hujah", foreign_key: "parent_id", dependent: :destroy
  has_many :debates, dependent: :destroy
  has_many :hashtag_hujahs, dependent: :destroy
  has_many :hashtags, through: :hashtag_hujahs
  belongs_to :parent, class_name: "Hujah", optional: true

  # Per-post visibility for TOP-LEVEL claims (replies inherit their parent). Enum keys
  # avoid the reserved words public/private. Default = visible_public. The `prefix`
  # makes predicates `visibility_visible_public?` / `visibility_followers_only?` /
  # `visibility_private_only?` so they don't collide with User#private? semantics.
  enum :visibility, {visible_public: 0, followers_only: 1, private_only: 2}, prefix: :visibility

  # Moderation (2026): the single visibility-enforcement point. `removed` content is
  # staff-only everywhere. The :moderation prefix avoids clashing with visibility_*
  # and the debate `status` enum — predicates are moderation_active? / moderation_removed?.
  enum :moderation_status, {active: 0, removed: 1}, default: :active, prefix: :moderation

  # Moderation (2026): the SQL counterpart to the visible_to? early gate below, for
  # LIST surfaces that never call visible_to? per record. Every feed/count sweep
  # site applies this unconditionally — staff read removed content on /moderation
  # and via direct URL, not in feeds.
  scope :not_removed, -> { where(moderation_status: :active) }

  # Secret ballot (finding 2a/A7): hide the per-stance breakdown until the electorate
  # is large enough that the published split can't be used to de-anonymize an individual
  # voter. Below this many total votes, surfaces show the total + the viewer's own stance
  # only. Reuses UserAnalytics::K (currently 3) as the SINGLE threshold source so the
  # analytics suppression and this cannot drift apart — do not mint a second literal.
  VOTE_BREAKDOWN_MIN = UserAnalytics::K

  # Total votes cast across all three stances (the electorate size). The single
  # replacement for the `agree_count + neutral_count + disagree_count` sum that was
  # duplicated across views/model.
  def total_votes
    agree_count.to_i + neutral_count.to_i + disagree_count.to_i
  end

  # Whether the per-stance breakdown may be shown. Uniform for everyone — including the
  # author: the secret-ballot threat treats the author as an observer too (the id-less
  # new_vote notification already refuses the author that de-anonymizing power).
  def breakdown_visible?
    total_votes >= VOTE_BREAKDOWN_MIN
  end

  # The ballot counts as serialized to clients: total is always present; the per-stance
  # breakdown is nil until breakdown_visible? (secret-ballot k-anonymity). Single source
  # for every serializer so the gate can't drift between them.
  def ballot_counts
    visible = breakdown_visible?
    {
      total_count: total_votes,
      agree_count: visible ? agree_count : nil,
      neutral_count: visible ? neutral_count : nil,
      disagree_count: visible ? disagree_count : nil
    }
  end

  validates :body, presence: true
  # 2026: a top-level claim must be a substantial statement (>= 8 chars); replies
  # (parent_id present) stay unconstrained so a terse "Agreed." still posts.
  validates :body, length: {minimum: 8}, if: -> { parent_id.nil? }

  # Has this user cast any vote on this hoojah? Used to gate replying (must vote first,
  # HujahPolicy#create?) and to render the argument composer's locked state.
  def voted_by?(user)
    user.present? && votes.exists?(user_id: user.id)
  end

  # Set by the feed controller after a single bulk `Debate.active.where(hujah_id:
  # [...])` query for the whole page (Phase 1.5), so #active_debate below reads it
  # for free instead of issuing one query per card. `defined?` (not `presence` or a
  # nil-check) is deliberate: it distinguishes "the controller preloaded and found
  # none" (explicit nil — trust it) from "nothing preloaded this record at all"
  # (fall back to a live lookup), which is what keeps this method correct OFF the
  # feed too (e.g. a future profile page that never sets this writer).
  attr_writer :preloaded_active_debate

  # This hoojah's current active Debate (challenger/opponent eager-loaded), or nil.
  # Prefers the feed's bulk preload; falls back to a per-record lookup so callers
  # outside the feed still get a correct answer, just not a preloaded one.
  def active_debate
    return @preloaded_active_debate if defined?(@preloaded_active_debate)
    debates.active.includes(:challenger, :opponent).first
  end

  # A hoojah is visible when BOTH the author is visible to the viewer (account
  # privacy, Slice 7b) AND the per-post visibility (2026) permits it. A REPLY
  # (parent_id present) is gated by the parent AND by the reply author's OWN account
  # privacy — dropping the latter regresses Slice 7b Gate 6 (a private user's reply
  # under a public claim must stay hidden from non-followers; the API show +
  # notification cards rely on this). Every content surface that renders a hoojah
  # gates through this.
  #
  # Moderation (2026): a removed hoojah is staff-only EVERYWHERE — including its
  # author, who learns via the moderation_removed notification instead. This gate is
  # the FIRST line, before the parent-recursion branch, so a removed REPLY is gated
  # on its OWN status, not just its parent's (an active reply under a removed parent
  # is still hidden by the parent recursion below).
  def visible_to?(viewer)
    return !!viewer&.can_moderate? if moderation_removed?
    return parent.visible_to?(viewer) && user.visible_to?(viewer) if parent_id
    return false unless user.visible_to?(viewer)

    case visibility
    when "visible_public" then true
    when "followers_only" then viewer == user || user.accepted_follower?(viewer)
    when "private_only" then viewer == user
    else false
    end
  end

  # Reply-visibility gate for a single parent's children — the SQL counterpart to
  # #visible_to? for a REPLY list. Extracted verbatim from HujahsController#show so
  # the HTML thread and the JSON API serializer share ONE gate (a private/blocked
  # author's reply must be hidden identically on both surfaces). One query, no N+1.
  # Signed-in: drop hidden (blocked/blocked-by) authors, then the per-viewer privacy
  # predicate; anonymous: public authors only. Accepted followers (+ self) see a
  # private author's reply via following_ids.
  def visible_children_for(viewer)
    # Moderation: E5 sweep — removed replies vanish from the HTML thread AND the API
    # serializer's children list/count (both share this one gate).
    scope = children.not_removed.includes(user: {avatar_attachment: :blob}).order(updated_at: :desc)
    scope = scope.where.not(user_id: viewer.hidden_user_ids) if viewer
    visible_ids = viewer ? viewer.following_ids + [viewer.id] : []
    scope.joins(:user).where("users.private = false OR hujahs.user_id IN (?)", visible_ids)
  end

  # Moderation (2026): the dismiss/remove/warn composition. Lifted off
  # ModerationController so the transactional invariants live next to the state they
  # protect. Each resolves the pending reports; only `by:` (the acting moderator) is
  # used for flag resolution — the notifications carry NO subject_user_id, the same
  # secret-ballot rule the vote notification follows (the moderator is never
  # identified to the author). `flags.pending.find_each` is idempotent by
  # construction: a second call finds zero pending flags and touches nothing.

  # Resolve every pending report; content untouched, no author notification.
  def dismiss_flags!(by:)
    flags.pending.find_each { |flag| flag.resolve!(by:, as: :dismissed) }
  end

  # Hide from everyone but staff + notify the author. One transaction: a half-applied
  # removal (hidden but unresolved flags, or the reverse) must not exist. The
  # `moderation_removed?` early return makes a second removal a no-op so the author is
  # never re-notified (L-1).
  def remove!(by:)
    return if moderation_removed?
    transaction do
      update!(moderation_status: :removed)
      flags.pending.find_each { |flag| flag.resolve!(by:, as: :actioned) }
      Notification.create!(user_id:, category: :moderation_removed, hujah_id: id)
    end
  end

  # Content untouched; author notified (anonymously); reports closed as actioned.
  def warn_author!(by:)
    transaction do
      flags.pending.find_each { |flag| flag.resolve!(by:, as: :actioned) }
      Notification.create!(user_id:, category: :moderation_warning, hujah_id: id)
    end
  end

  # @handle mention pattern. The `(?<!\w)` lookbehind means an `@` preceded by a
  # word char (e.g. inside an email `foo@bar`) is NOT a mention.
  MENTION_RE = /(?<!\w)@([a-zA-Z0-9_]+)/

  # #hashtag pattern — same `(?<!\w)` lookbehind guard as mentions so `a#b` (a `#`
  # mid-word, e.g. `C#Sharp`) isn't a tag. Unicode letters allowed (Malay names);
  # digits and underscore permitted after a leading letter. Kept in sync with the
  # HujahsHelper#format_body linkify pass, which reuses this constant.
  HASHTAG_RE = /(?<!\w)#(\p{L}[\p{L}0-9_]*)/

  after_save_commit :sync_hashtags

  # Reconcile this hoojah's hashtag joins with the tags currently in its body. Runs
  # on create AND edit (unlike notify_mentions which is create-only) because the tag
  # set must track body edits. Runs after_save_commit so it never executes inside
  # cast_vote's transaction and always sees the persisted body. Canonical `name` is
  # lower-cased; `display` keeps the first-seen casing. Capped at 10 tags/hoojah.
  def sync_hashtags
    raw = body.to_s.scan(HASHTAG_RE).flatten.uniq(&:downcase).first(10)
    wanted = raw.index_by { |r| Hashtag.canonical(r) }
    Hashtag.transaction do
      tags = wanted.map do |name, original|
        Hashtag.create_with(display: original).find_or_create_by!(name: name)
      end
      self.hashtags = tags # replaces the join set; counter_cache adjusts on add/remove
    end
  end

  # Top-level visibility for LIST surfaces (search). Replies are excluded on purpose:
  # Hujah#visible_to? recurses through parent.visible_to?, which is not expressible in
  # one SQL predicate.
  scope :visible_to, ->(viewer) {
    # Moderation: E3 sweep — removed claims never surface on search (Hujah.search
    # feeds off this scope).
    base = where(parent_id: nil).not_removed.joins(:user)
    if viewer
      ids = viewer.following_ids # accepted-only
      base.where(
        "(users.private = FALSE OR hujahs.user_id = :s OR hujahs.user_id IN (:f)) AND " \
        "(hujahs.visibility = 0 OR hujahs.user_id = :s OR (hujahs.visibility = 1 AND hujahs.user_id IN (:f)))",
        s: viewer.id, f: ids.presence || [-1]
      ).where.not(user_id: viewer.hidden_user_ids)
    else
      base.where(visibility: :visible_public).where(users: {private: false})
    end
  }

  # Full-text search (Phase 2.2). Reuses .visible_to (top-level only, which is why
  # a reply's body can never surface here — see that scope's comment) so a search
  # result can never leak content the feed/profile wouldn't already show. `?` bind
  # PLUS `sanitize_sql_like` on the term: the bind alone stops SQL injection but
  # NOT a `%`/`_` in the user's own query being (mis)read as a wildcard.
  scope :search, ->(q, viewer:) {
    visible_to(viewer).where("hujahs.body ILIKE ?", "%#{sanitize_sql_like(q)}%").limit(8)
  }

  # Home timeline: top-level hoojahs from the people you follow, plus your own,
  # minus any hidden (blocked/blocked-by) author. The follow-removal on block already
  # drops a blocked author from `following_ids`; the `hidden_user_ids` exclusion is
  # belt-and-suspenders (Slice 7).
  scope :timeline_for, ->(user) {
    # Moderation: E2 sweep — the Following feed never shows removed claims.
    where(parent_id: nil).not_removed.where(user_id: user.following_ids + [user.id])
      .where.not(user_id: user.hidden_user_ids)
  }

  after_create_commit :notify_parent_owner, if: :has_parent?
  after_create_commit :notify_mentions # create only -- edit-mention handling deferred with the edit UI
  # Off the hot path (after commit, never inside cast_vote's transaction): the
  # first top-level hoojah earns first_hoojah; the first reply earns first_argument.
  after_create_commit :award_authoring_badge

  # Moderation (2026): a cached trending hoojah must not linger up to 15 min after
  # removal. Mirrors User#bust_trending_cache (the private-flip case) — bust on the
  # moderation flip so the next Hujah.trending recomputes without the removed id.
  after_update_commit :bust_trending_cache, if: -> { saved_change_to_moderation_status? }

  extend FriendlyId

  friendly_id :slug_source, use: [:slugged, :history]

  def slug_source
    ActionController::Base.helpers.strip_tags(body.to_s).split.first(10).join(" ")
  end

  def should_generate_new_friendly_id?
    will_save_change_to_body? || slug.blank?
  end

  # The closed vote domain, in one place. `votes.vote` stores these integers;
  # everything user-facing (stance colours, CSS classes, the serializer) speaks the
  # string. COUNTER_FOR is derived so the two can never drift apart.
  STANCES = {1 => "agree", 2 => "neutral", 3 => "disagree"}.freeze
  COUNTER_FOR = STANCES.transform_values { |stance| :"#{stance}_count" }.freeze

  # Trending top-level hoojahs by Hacker-News gravity on TOTAL activity (votes +
  # child arguments), decayed by age. Computed on read and cached for 15 min: the
  # cache stores only the ordered ids, then we reload `where(id:).includes(:user)`
  # and re-sort into cache order. The `updated_at > 48h` candidate filter is the
  # recency gate (voting bumps updated_at via increment!). No background job.
  def self.trending
    ids = Rails.cache.fetch("trending:v1", expires_in: 15.minutes) do
      # Slice 7b: trending candidates exclude a private author's hoojahs (with the
      # User#after_update_commit cache-bust so the flip is reflected immediately).
      where(parent_id: nil).not_removed.where("hujahs.updated_at > ?", 48.hours.ago) # Moderation: E4 — removed claims never trend
        .where(visibility: :visible_public) # 2026: a non-public claim never trends
        .joins(:user).where(users: {private: false}).to_a
        .map { |h|
          [h.id, ((h.agree_count + h.neutral_count + h.disagree_count + h.children.size).to_f /
            (((Time.current - h.created_at) / 3600) + 2)**1.5)]
        }
        .sort_by { |_, score| -score }.first(10).map(&:first)
    end
    where(id: ids).includes(user: {avatar_attachment: :blob}).sort_by { |h| ids.index(h.id) }
  end

  def cast_vote(by:, choice:, conviction: false)
    choice = choice.to_i
    return unless COUNTER_FOR.key?(choice)

    transaction do
      # `.lock` takes a FOR UPDATE row lock so the conviction? re-check below reads
      # committed state — two concurrent upgrades can't both see conviction=false and
      # double-count conviction_count. (A unique index on votes[hujah_id, user_id] is
      # on the backlog to also close the concurrent-first-vote double-row race; see
      # HANDOVER.)
      existing = votes.lock.find_by(user_id: by.id)
      if existing
        return if existing.conviction? # locked forever — no stance change, no re-lock

        previous = existing.vote.last
        if previous == choice
          # Same stance: allow upgrading a plain vote to a conviction (locked) vote.
          if conviction
            existing.update!(conviction: true)
            increment!(:conviction_count)
          end
          return
        end

        # A locked row already early-returned above, so `existing.conviction` is false
        # here: a stance change may itself be a conviction (hold-charging a different
        # stance than the current tap-vote), which locks the switched vote and counts once.
        existing.update!(vote: existing.vote + [choice], conviction: conviction)
        increment!(:conviction_count) if conviction
        decrement!(COUNTER_FOR[previous]) if COUNTER_FOR.key?(previous)
        increment!(COUNTER_FOR[choice])
      else
        votes.create!(user: by, vote: [choice], conviction: conviction)
        increment!(COUNTER_FOR[choice])
        increment!(:conviction_count) if conviction
        # Privacy: the new_vote notification deliberately carries NO subject_user_id.
        # Votes are an effectively secret ballot; recording the first voter's id here
        # let the owner de-anonymize them via NotificationSerializer (Slice 5, Part A).
        Notification.create!(user_id: user_id, category: :new_vote, hujah_id: id)
      end
    end
  end

  def is_parent?
    parent.nil?
  end

  def has_parent?
    parent != nil
  end

  # The viewer's current stance on this hoojah as a STANCES string, or nil.
  # One query — this runs per card on the feed, the hottest read path here.
  # `votes.vote` is a legacy array column APPENDED to on every cast, so the last
  # element is the current stance (and `&.last` on an empty array is nil).
  # No `joins(:user)`: `User has_many :votes, dependent: :destroy`, so a vote row
  # whose user is gone cannot exist and the join could only ever cost a table scan.
  def current_user_vote(logged_in: nil, current_user_id: nil)
    return unless logged_in
    STANCES[votes.find_by(user_id: current_user_id)&.vote&.last]
  end

  private

  def bust_trending_cache = Rails.cache.delete("trending:v1")

  def award_authoring_badge
    UserBadge.award(user, is_parent? ? "first_hoojah" : "first_argument")
  end

  def notify_parent_owner
    Notification.create!(user_id: parent.user_id, category: :new_hoojah_response,
      hujah_id: parent.id, subject_user_id: user_id)
  end

  # Inline, create-only, idempotent (matches every existing notification
  # callback). Cap 10 unique handles/hoojah (anti-spam + dedup); skip self and
  # unknown handles; the `exists?` guard makes it "at most once per (hoojah,
  # mentioner, mentioned)" -- robust to any future edit churn without body-diffing.
  def notify_mentions
    handles = body.scan(MENTION_RE).flatten.uniq.first(10)
    return if handles.empty? # skip the lookup (and hidden_user_ids) for the common no-mention case
    # Slice 7: never notify a hidden (blocked/blocked-by) user of a mention.
    User.where(username: handles).where.not(id: user_id).where.not(id: user.hidden_user_ids).each do |u|
      next if Notification.exists?(user: u, hujah_id: id, category: :mention, subject_user_id: user_id)
      Notification.create!(user: u, category: :mention, hujah_id: id, subject_user_id: user_id)
    end
  end
end
