class Hujah < ApplicationRecord
  belongs_to :user
  has_many :votes, dependent: :destroy
  has_many :flags, dependent: :destroy
  has_many :children, class_name: "Hujah", foreign_key: "parent_id", dependent: :destroy
  has_many :debates, dependent: :destroy
  has_many :hashtag_hujahs, dependent: :destroy
  has_many :hashtags, through: :hashtag_hujahs
  # Notifications carry a nullable `hujah_id` with NO DB foreign key (schema:
  # NB: notifications are deliberately NOT cascaded. `Notification belongs_to :hujah,
  # optional: true` and the serializer/views are nil-safe (Slice 11 Task 9), so a
  # notification whose hoojah was deleted SURVIVES and renders without the hoojah block —
  # a `dependent: :destroy` here would erase still-meaningful "someone mentioned you"
  # rows and break spec/requests/api/v1/notifications_spec's no-500 guarantee.
  belongs_to :parent, class_name: "Hujah", optional: true

  # Slice 3: custom stance labels are IMMUTABLE after create. Under the Rails 8.1 default
  # (raise_on_assign_to_attr_readonly), assigning one on a persisted record raises
  # ActiveRecord::ReadonlyAttributeError — loud by design: no request path can reach it
  # (edit_params never permits label keys; the API has no hujah update), so a raise here
  # signals a programmer bug, not user tampering. The create-time eligibility coercion
  # below is the actual tamper gate.
  attr_readonly :agree_label, :neutral_label, :disagree_label

  # A HARD destroy is only offered on a "leaf" claim. A hoojah with replies or debates
  # carries other people's content (child arguments, a whole debate transcript) that the
  # `dependent: :destroy` cascades above would wipe away — HujahsController#destroy refuses
  # instead of silently deleting it. `any?` on an unloaded association issues an EXISTS
  # (not a load), so this stays two cheap queries.
  def deletable?
    !(children.any? || debates.any?)
  end

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

  # Slice 1 (editable hujah): the body edit window. An author may fix their wording
  # for a short grace period after posting — closed PERMANENTLY at 15 minutes OR the
  # first conviction, whichever comes first. Applies to top-level claims AND replies.
  EDIT_WINDOW = 15.minutes

  # Body is editable only while the window is open: active (not moderator-removed),
  # no conviction cast yet, within EDIT_WINDOW of creation. `moderation_active?`
  # already covers the removed case; the policy repeats `!moderation_removed?` for
  # symmetry with destroy?.
  def body_editable? = moderation_active? && conviction_count.zero? && created_at > EDIT_WINDOW.ago

  # Has the body been edited since posting? Driven by the body_edited_at stamp, NOT
  # updated_at (which cast_vote bumps on every vote via the counter increment!s).
  def body_edited? = body_edited_at.present?

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

  # Bulk visible-reply COUNT for many parents at once — the count-surface
  # counterpart to #visible_children_for (same gate: not_removed; drop hidden
  # authors when signed in; per-viewer privacy predicate; anonymous → public
  # authors only). Returns {parent_id => count}; parents with zero visible
  # replies are ABSENT from the hash (callers treat missing as 0). Mirrors that
  # gate so a badge count matches exactly what the viewer would see after
  # clicking through — a removed/blocked/private-author grandchild is not
  # counted. ONE grouped query for the whole parent set, no N+1.
  def self.visible_reply_counts_for(parent_ids, viewer)
    return {} if parent_ids.blank?

    scope = where(parent_id: parent_ids).not_removed
    scope = scope.where.not(user_id: viewer.hidden_user_ids) if viewer
    visible_ids = viewer ? viewer.following_ids + [viewer.id] : []
    scope.joins(:user)
      .where("users.private = false OR hujahs.user_id IN (?)", visible_ids)
      .group(:parent_id)
      .count
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

  # Slice 3: normalise then coerce, both create-only (columns are attr_readonly after).
  # enforce_stance_label_eligibility only checks parent_id + author eligibility, so the
  # order is defensive (future-proofs an eligibility check that might consult
  # custom_stances?), not currently load-bearing.
  before_validation :normalize_stance_labels, on: :create
  before_validation :enforce_stance_label_eligibility, on: :create

  after_create_commit :notify_parent_owner, if: :has_parent?
  after_create_commit :notify_mentions # create-only; newly-added mentions on a body edit are handled by notify_new_mentions below
  # Slice 1: edit-aware mention notification. notify_mentions above stays CREATE-only;
  # on a body edit this fires for ONLY the handles newly added to the body (diff
  # old-vs-new), so pre-existing mentions never re-fire. saved_change_to_body? is
  # false during cast_vote (which never touches body), so a vote never triggers it.
  after_update_commit :notify_new_mentions, if: :saved_change_to_body?
  # Off the hot path (after commit, never inside cast_vote's transaction): the
  # first top-level hoojah earns first_hoojah; the first reply earns first_argument.
  after_create_commit :award_authoring_badge

  # Moderation (2026): a cached trending hoojah must not linger up to 15 min after
  # removal. Mirrors User#bust_trending_cache (the private-flip case) — bust on the
  # moderation flip so the next Hujah.trending recomputes without the removed id.
  after_update_commit :bust_trending_cache, if: -> { saved_change_to_moderation_status? }

  # Slice 1: record WHEN the body was last edited, but ONLY on an actual body change.
  # updated_at is unreliable as an "edited" signal — cast_vote's increment!/decrement!
  # on the counter columns touches updated_at without touching the body. before_update
  # (not after) so the stamp persists in the SAME UPDATE as the new body/slug.
  before_update :stamp_body_edited_at, if: :will_save_change_to_body?

  extend FriendlyId

  friendly_id :slug_source, use: [:slugged, :history]

  def slug_source
    ActionController::Base.helpers.strip_tags(body.to_s).split.first(10).join(" ")
  end

  def should_generate_new_friendly_id?
    will_save_change_to_body? || slug.blank?
  end

  # Slice 2 (editable-hujah): detach this reply into a standalone top-level claim. The
  # whole subtree travels with it (descendants keep pointing here). vote: nil drops the
  # stance-toward-parent context — a top-level claim has no parent to take a stance on.
  # This is where the top-level `body >= 8` validation first applies (parent_id is now
  # nil), so a too-short reply raises ActiveRecord::RecordInvalid here and the whole
  # promotion rolls back; the controller rescues it.
  #
  # Slug regeneration is deliberate but NOT via `slug: nil`: FriendlyId 5.7's
  # History#scope_for_slug_generator excludes THIS record's own historic slugs from
  # conflict detection ("allow reversion back to a previously used slug"), so a blanked
  # slug regenerates to the byte-identical value from the same body — verified. Appending
  # a short random suffix forces a genuinely fresh canonical slug; the old slug already
  # sits in friendly_id_slugs (recorded on create) and keeps redirecting via
  # Hujah.friendly.find (:history).
  def promote!
    transaction do
      update!(parent_id: nil, vote: nil)
      update!(slug: "#{slug}-#{SecureRandom.alphanumeric(6).downcase}")
    end
  end

  # The closed vote domain, in one place. `votes.vote` stores these integers;
  # everything user-facing (stance colours, CSS classes, the serializer) speaks the
  # string. COUNTER_FOR is derived so the two can never drift apart.
  STANCES = {1 => "agree", 2 => "neutral", 3 => "disagree"}.freeze
  COUNTER_FOR = STANCES.transform_values { |stance| :"#{stance}_count" }.freeze

  # Slice 3 — per-position custom stance labels. STANCE_LABEL_COLUMNS maps the same
  # 1/2/3 vote positions STANCES uses to the nullable string column that overrides each
  # default token. A column is nil when uncustomised, so `default` and `custom` are a
  # pure presence test (see #custom_stances? / #default_hujah?).
  STANCE_LABEL_COLUMNS = {1 => :agree_label, 2 => :neutral_label, 3 => :disagree_label}.freeze
  CUSTOM_LABEL_MAX = 24

  # The label shown for vote position 1/2/3 on THIS record's own surfaces: the custom
  # label when set, else the default STANCES token. Replies always render defaults —
  # only a top-level claim (parent_id nil) may carry custom labels.
  def stance_label(position)
    default = STANCES.fetch(position)
    return default unless parent_id.nil?
    self[STANCE_LABEL_COLUMNS.fetch(position)].presence || default
  end

  # Does this hoojah carry ANY custom label? (Presence test — a column is nil unless
  # customised.) Drives the badge award and the eligibility count's exclusion.
  def custom_stances?
    agree_label.present? || neutral_label.present? || disagree_label.present?
  end

  # A "default hoojah" for the Slice-3 eligibility count: top-level and uncustomised.
  def default_hujah?
    parent_id.nil? && !custom_stances?
  end

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

  def stamp_body_edited_at = self.body_edited_at = Time.current

  def award_authoring_badge
    UserBadge.award(user, is_parent? ? "first_hoojah" : "first_argument")
    # Slice 3: a top-level claim that carries any custom label earns the custom badge.
    # custom_stances? reads the persisted (already-coerced) columns, so an ineligible
    # author whose labels were nilled never qualifies.
    UserBadge.award(user, "first_custom_hoojah") if is_parent? && custom_stances?
  end

  # Trim, collapse internal whitespace (which also strips newlines), cap at
  # CUSTOM_LABEL_MAX, and treat a value equal to its default token (case-insensitive) as
  # "not customised" → nil. Empty/blank → nil.
  def normalize_stance_labels
    STANCES.each do |position, default_token|
      column = STANCE_LABEL_COLUMNS.fetch(position)
      raw = self[column]
      next if raw.nil?
      cleaned = raw.to_s.gsub(/\s+/, " ").strip[0, CUSTOM_LABEL_MAX].strip
      cleaned = nil if cleaned.blank? || cleaned.casecmp?(default_token)
      self[column] = cleaned
    end
  end

  # Custom labels survive ONLY on a top-level claim by an eligible author; anything else
  # (a reply, or an author under the 10-default-post threshold) has them coerced to nil,
  # so a hand-crafted POST cannot bypass the composer's server-side gate.
  def enforce_stance_label_eligibility
    return if parent_id.nil? && user&.can_customize_stances?
    self.agree_label = nil
    self.neutral_label = nil
    self.disagree_label = nil
  end

  def notify_parent_owner
    Notification.create!(user_id: parent.user_id, category: :new_hoojah_response,
      hujah_id: parent.id, subject_user_id: user_id)
  end

  # Inline, create-only, idempotent (matches every existing notification callback).
  # All the anti-spam/dedup/skip/exists? mechanics now live in the shared writer
  # notify_mention_handles below; this just feeds it every handle in the new body.
  def notify_mentions
    notify_mention_handles(mention_handles(body))
  end

  # Edit-only (Slice 1): notify ONLY handles present in the NEW body but not the OLD.
  # saved_change_to_body returns [before, after] in the after_update_commit callback.
  def notify_new_mentions
    before, after = saved_change_to_body
    notify_mention_handles(mention_handles(after) - mention_handles(before))
  end

  # Parse @handles out of arbitrary text -- deduped, capped at 10 (anti-spam). Shared
  # by the create-time notify_mentions and the edit-time notify_new_mentions diff.
  def mention_handles(text)
    text.to_s.scan(MENTION_RE).flatten.uniq.first(10)
  end

  # Shared writer: skip empty; skip self + hidden (blocked/blocked-by) users; the
  # exists? guard makes it "at most once per (hoojah, mentioner, mentioned)".
  # Slice 7: never notify a hidden (blocked/blocked-by) user of a mention.
  def notify_mention_handles(handles)
    return if handles.empty? # skip the lookup (and hidden_user_ids) for the common no-mention case
    User.where(username: handles).where.not(id: user_id).where.not(id: user.hidden_user_ids).each do |u|
      next if Notification.exists?(user: u, hujah_id: id, category: :mention, subject_user_id: user_id)
      Notification.create!(user: u, category: :mention, hujah_id: id, subject_user_id: user_id)
    end
  end
end
