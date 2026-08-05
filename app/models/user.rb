class User < ApplicationRecord
  has_many :hujahs, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :flags, dependent: :destroy
  has_many :challenged_debates, class_name: "Debate", foreign_key: :challenger_id, dependent: :destroy
  has_many :defended_debates, class_name: "Debate", foreign_key: :opponent_id, dependent: :destroy
  has_many :debate_turns, dependent: :destroy
  has_many :user_badges, dependent: :destroy

  # Follow graph. active_follows = follows I initiated (I am the follower);
  # passive_follows = follows pointed at me (I am the followed).
  has_many :active_follows, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  # `following`/`followers` are ACCEPTED-ONLY (Slice 7b). The through-association
  # scope makes `following_ids`, counts, and the list pages all accepted-only in one
  # place — a pending follow request never counts as a follow anywhere. Existing rows
  # were backfilled to accepted; new private-target follows land pending.
  has_many :following, -> { where(follows: {status: Follow.statuses[:accepted]}) },
    through: :active_follows, source: :followed
  has_many :passive_follows, class_name: "Follow", foreign_key: :followed_id, dependent: :destroy
  has_many :followers, -> { where(follows: {status: Follow.statuses[:accepted]}) },
    through: :passive_follows, source: :follower

  # Block graph. blocks_made = blocks I initiated; blocks_received = blocks pointed
  # at me. Block is bidirectional invisibility/interaction cutoff (Slice 7).
  has_many :blocks_made, class_name: "Block", foreign_key: :blocker_id, dependent: :destroy
  has_many :blocks_received, class_name: "Block", foreign_key: :blocked_id, dependent: :destroy

  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable

  before_validation { self.email = email.to_s.downcase.strip }

  RESERVED_USERNAMES = %w[login signup logout password edit cancel new hoojah hoojahs u users
    notifications rails api admin].freeze

  validates :full_name, presence: true
  validates :username, presence: true, uniqueness: true,
    format: {with: /\A[a-zA-Z0-9_]+\z/},
    exclusion: {in: RESERVED_USERNAMES}
  # Anchored at both ends with no whitespace (\S+\z): the trailing \z blocks
  # newline-injection (a `\n` after a valid prefix) that an unanchored regex would
  # allow — closing the M7 link-XSS finding brakeman flags as Format Validation.
  validates :link, format: {with: %r{\Ahttps?://\S+\z}i}, allow_blank: true
  validate :photo_from_cloudinary

  after_create :assign_random_photo

  # Slice 7b (T-1): a cached trending hoojah must not stay visible after its author
  # goes private. Trending caches only ids for 15 min; busting the cache on the
  # privacy flip forces a recompute (which excludes the now-private author) instead
  # of leaking the hoojah for up to 15 minutes.
  after_update_commit :bust_trending_cache, if: -> { saved_change_to_private? }

  def self.random_photo
    [
      "https://res.cloudinary.com/hoojah/image/upload/v1586909321/user_photo_2.gif",
      "https://res.cloudinary.com/hoojah/image/upload/v1586909320/user_photo_4.gif",
      "https://res.cloudinary.com/hoojah/image/upload/v1586909321/user_photo_6.gif",
      "https://res.cloudinary.com/hoojah/image/upload/v1586909320/user_photo_7.gif"
    ].sample
  end

  def unread_notifications_count
    notifications.unread.count
  end

  # The single visibility gate every private-content surface consults (Slice 7b).
  # Public users are visible to everyone (incl. anonymous); a private user is
  # visible only to themselves and to an ACCEPTED follower. Deliberately NOT
  # memoized — most callers invoke it once, and the list surfaces gate in SQL.
  def visible_to?(viewer)
    !private? || viewer == self || accepted_follower?(viewer)
  end

  def accepted_follower?(viewer)
    viewer.present? && passive_follows.accepted.exists?(follower_id: viewer.id)
  end

  # The single source of truth every block filter/policy consults (bidirectional):
  # users I blocked ∪ users who blocked me. Memoized because the trending
  # post-filter consults it once per candidate — current_user is one memoized
  # instance per request, so this is safe.
  def hidden_user_ids
    @hidden_user_ids ||= (blocks_made.pluck(:blocked_id) + blocks_received.pluck(:blocker_id)).uniq
  end

  # Earned badges as their registry hashes (name/description/icon). `filter_map`
  # drops any award whose key was renamed/removed from Badge::REGISTRY so a future
  # registry edit can't 500 the public profile.
  def badges = user_badges.filter_map { |ub| Badge::REGISTRY[ub.badge_key] }

  def photo_from_cloudinary
    return if photo.blank?
    uri = URI.parse(photo)
    ok = uri.scheme == "https" && uri.host == "res.cloudinary.com" && uri.path.start_with?("/hoojah/")
    errors.add(:photo, "must be a Hoojah Cloudinary URL") unless ok
  rescue URI::InvalidURIError
    errors.add(:photo, "is not a valid URL")
  end

  private

  def bust_trending_cache = Rails.cache.delete("trending:v1")

  def assign_random_photo
    update_column(:photo, User.random_photo) if photo.blank?
  end
end
