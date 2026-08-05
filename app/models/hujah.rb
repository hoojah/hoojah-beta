class Hujah < ApplicationRecord
  belongs_to :user
  has_many :votes, dependent: :destroy
  has_many :flags, dependent: :destroy
  has_many :children, class_name: "Hujah", foreign_key: "parent_id", dependent: :destroy
  has_many :debates, dependent: :destroy
  belongs_to :parent, class_name: "Hujah", optional: true

  validates :body, presence: true

  # @handle mention pattern. The `(?<!\w)` lookbehind means an `@` preceded by a
  # word char (e.g. inside an email `foo@bar`) is NOT a mention.
  MENTION_RE = /(?<!\w)@([a-zA-Z0-9_]+)/

  # Home timeline: top-level hoojahs from the people you follow, plus your own.
  # Uses the association's `_ids` (not raw SQL). Slice 7 adds a `hidden_user_ids`
  # exclusion here (blocked authors are already dropped from `following_ids` when a
  # block removes the follow; the exclusion is belt-and-suspenders).
  scope :timeline_for, ->(user) {
    where(parent_id: nil).where(user_id: user.following_ids + [user.id])
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

  COUNTER_FOR = {1 => :agree_count, 2 => :neutral_count, 3 => :disagree_count}.freeze

  # Trending top-level hoojahs by Hacker-News gravity on TOTAL activity (votes +
  # child arguments), decayed by age. Computed on read and cached for 15 min: the
  # cache stores only the ordered ids, then we reload `where(id:).includes(:user)`
  # and re-sort into cache order. The `updated_at > 48h` candidate filter is the
  # recency gate (voting bumps updated_at via increment!). No background job.
  def self.trending
    ids = Rails.cache.fetch("trending:v1", expires_in: 15.minutes) do
      where(parent_id: nil).where("updated_at > ?", 48.hours.ago).to_a
        .map { |h|
          [h.id, ((h.agree_count + h.neutral_count + h.disagree_count + h.children.size).to_f /
            (((Time.current - h.created_at) / 3600) + 2)**1.5)]
        }
        .sort_by { |_, score| -score }.first(10).map(&:first)
    end
    where(id: ids).includes(:user).sort_by { |h| ids.index(h.id) }
  end

  def cast_vote(by:, choice:)
    choice = choice.to_i
    return unless COUNTER_FOR.key?(choice)

    transaction do
      existing = votes.find_by(user_id: by.id)
      if existing
        previous = existing.vote.last
        return if previous == choice

        existing.update!(vote: existing.vote + [choice])
        decrement!(COUNTER_FOR[previous]) if COUNTER_FOR.key?(previous)
        increment!(COUNTER_FOR[choice])
      else
        votes.create!(user: by, vote: [choice])
        increment!(COUNTER_FOR[choice])
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

  def has_children?
    children.exists?
  end

  def current_user_vote(logged_in: nil, current_user_id: nil)
    if logged_in
      if votes.joins(:user).find_by(user_id: current_user_id).nil?
        nil
      else
        vote = votes.joins(:user).find_by(user_id: current_user_id).vote.last
        if vote == 1
          "agree"
        elsif vote == 2
          "neutral"
        elsif vote == 3
          "disagree"
        end
      end
    end
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
    User.where(username: handles).where.not(id: user_id).each do |u|
      next if Notification.exists?(user: u, hujah_id: id, category: :mention, subject_user_id: user_id)
      Notification.create!(user: u, category: :mention, hujah_id: id, subject_user_id: user_id)
    end
  end
end
