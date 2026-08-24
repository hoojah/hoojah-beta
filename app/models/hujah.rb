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

  validates :body, presence: true
  # 2026: a top-level claim must be a substantial statement (>= 8 chars); replies
  # (parent_id present) stay unconstrained so a terse "Agreed." still posts.
  validates :body, length: {minimum: 8}, if: -> { parent_id.nil? }

  # Has this user cast any vote on this hoojah? Used to gate replying (must vote first,
  # HujahPolicy#create?) and to render the argument composer's locked state.
  def voted_by?(user)
    user.present? && votes.exists?(user_id: user.id)
  end

  # A hoojah is visible when BOTH the author is visible to the viewer (account
  # privacy, Slice 7b) AND the per-post visibility (2026) permits it. A REPLY
  # (parent_id present) is gated by the parent AND by the reply author's OWN account
  # privacy — dropping the latter regresses Slice 7b Gate 6 (a private user's reply
  # under a public claim must stay hidden from non-followers; the API show +
  # notification cards rely on this). Every content surface that renders a hoojah
  # gates through this.
  def visible_to?(viewer)
    return parent.visible_to?(viewer) && user.visible_to?(viewer) if parent_id
    return false unless user.visible_to?(viewer)

    case visibility
    when "visible_public" then true
    when "followers_only" then viewer == user || user.accepted_follower?(viewer)
    when "private_only" then viewer == user
    else false
    end
  end

  # @handle mention pattern. The `(?<!\w)` lookbehind means an `@` preceded by a
  # word char (e.g. inside an email `foo@bar`) is NOT a mention.
  MENTION_RE = /(?<!\w)@([a-zA-Z0-9_]+)/

  # Home timeline: top-level hoojahs from the people you follow, plus your own,
  # minus any hidden (blocked/blocked-by) author. The follow-removal on block already
  # drops a blocked author from `following_ids`; the `hidden_user_ids` exclusion is
  # belt-and-suspenders (Slice 7).
  scope :timeline_for, ->(user) {
    where(parent_id: nil).where(user_id: user.following_ids + [user.id])
      .where.not(user_id: user.hidden_user_ids)
  }

  after_create_commit :notify_parent_owner, if: :has_parent?
  after_create_commit :notify_mentions # create only -- edit-mention handling deferred with the edit UI
  # Off the hot path (after commit, never inside cast_vote's transaction): the
  # first top-level hoojah earns first_hoojah; the first reply earns first_argument.
  after_create_commit :award_authoring_badge

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
      where(parent_id: nil).where("hujahs.updated_at > ?", 48.hours.ago)
        .where(visibility: :visible_public) # 2026: a non-public claim never trends
        .joins(:user).where(users: {private: false}).to_a
        .map { |h|
          [h.id, ((h.agree_count + h.neutral_count + h.disagree_count + h.children.size).to_f /
            (((Time.current - h.created_at) / 3600) + 2)**1.5)]
        }
        .sort_by { |_, score| -score }.first(10).map(&:first)
    end
    where(id: ids).includes(:user).sort_by { |h| ids.index(h.id) }
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
