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

  has_one_attached :avatar

  before_validation { self.email = email.to_s.downcase.strip }

  RESERVED_USERNAMES = %w[login signup logout password edit cancel new hoojah hoojahs u users
    notifications rails api admin].freeze

  MAX_AVATAR_BYTES = 5.megabytes
  ALLOWED_AVATAR_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  validates :full_name, presence: true
  validates :username, presence: true, uniqueness: true,
    format: {with: /\A[a-zA-Z0-9_]+\z/},
    exclusion: {in: RESERVED_USERNAMES}
  # Anchored at both ends with no whitespace (\S+\z): the trailing \z blocks
  # newline-injection (a `\n` after a valid prefix) that an unanchored regex would
  # allow — closing the M7 link-XSS finding brakeman flags as Format Validation.
  validates :link, format: {with: %r{\Ahttps?://\S+\z}i}, allow_blank: true
  validate :photo_from_cloudinary
  validate :avatar_is_valid_image

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

  # Profile "Hoojahs" tab visibility — top-level hoojahs this viewer may see,
  # gated by per-post visibility (2026). Extracted from UsersController#profile_tab_list
  # so the HTML profile and the API UserSerializer share ONE gate. Block filtering is
  # intentionally absent: every row here is authored by `self`, and Block does not hide
  # a user's own profile (Slice 7 direct-URL boundary) — the account-level gate is the
  # caller's responsibility (HTML: _gated_header; API: users#show visible_to? → 404).
  def visible_hujahs_for(viewer)
    base =
      if viewer == self
        hujahs
      elsif accepted_follower?(viewer)
        hujahs.where(visibility: [:visible_public, :followers_only])
      else
        hujahs.where(visibility: :visible_public)
      end
    base.where(parent_id: nil).includes(:user).order(updated_at: :desc)
  end

  # SQL counterpart to #visible_to? for LIST surfaces (search, Phase 2). Must match
  # #visible_to? exactly.
  scope :visible_to, ->(viewer) {
    if viewer
      where("users.private = FALSE OR users.id = :s OR users.id IN (:f)",
        s: viewer.id, f: viewer.following_ids.presence || [-1])
        .where.not(id: viewer.hidden_user_ids)
    else
      where(private: false)
    end
  }

  # Full-text search (Phase 2.2). Reuses .visible_to (above), so a private account
  # can never surface to a non-follower via search even though it matched. `?`
  # bind PLUS `sanitize_sql_like` on the term — the bind alone stops SQL injection
  # but not the user's own `%`/`_` being read as a wildcard.
  scope :search, ->(q, viewer:) {
    like = "%#{sanitize_sql_like(q)}%"
    visible_to(viewer).where("username ILIKE :l OR full_name ILIKE :l", l: like).limit(8)
  }

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

  def avatar_is_valid_image
    return unless avatar.attached?
    unless ALLOWED_AVATAR_TYPES.include?(avatar.blob.content_type)
      errors.add(:avatar, "must be a PNG, JPEG, GIF, or WebP image")
    end
    if avatar.blob.byte_size > MAX_AVATAR_BYTES
      errors.add(:avatar, "must be smaller than 5 MB")
    end
  end

  def bust_trending_cache = Rails.cache.delete("trending:v1")

  def assign_random_photo
    update_column(:photo, User.random_photo) if photo.blank?
  end
end
