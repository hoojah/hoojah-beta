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
    :recoverable, :rememberable, :validatable,
    :omniauthable, omniauth_providers: [:google_oauth2]

  has_one_attached :avatar

  # Moderation (2026): the moderator identity. No prefix — moderator?/admin? don't
  # collide with anything today.
  enum :role, {member: 0, moderator: 1, admin: 2}, default: :member

  # The ONLY capability gate the rest of the app reads (policies, nav, views).
  def can_moderate? = moderator? || admin?

  # Slice 3: a per-post custom-stance-label author must have posted 10+ DEFAULT
  # top-level hoojahs — top-level (parent_id nil), not moderator-removed, and carrying
  # no custom labels (all three label columns nil). Custom posts don't count toward
  # unlocking; this is the eligibility gate the composer UI and the create-time
  # coercion both consult.
  def can_customize_stances?
    hujahs.where(parent_id: nil).not_removed
      .where(agree_label: nil, neutral_label: nil, disagree_label: nil).count >= 10
  end

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

  # Auto-linking by email is safe ONLY because omniauth-google-oauth2 populates
  # info.email from Google's verified_email (nil unless the address is verified).
  # Do not reuse this method for a provider without that guarantee.
  def self.from_omniauth(auth)
    if (user = find_by(provider: auth.provider, uid: auth.uid))
      return user
    end

    email = auth.info.email.to_s.downcase.strip
    if email.blank?
      user = new
      user.errors.add(:base, "Google did not provide a verified email address.")
      return user
    end

    if (user = find_by(email: email))
      if user.provider.present? && user.uid != auth.uid
        user.errors.add(:base, "This email is already linked to a different Google account.")
        return user
      end
      user.update_columns(provider: auth.provider, uid: auth.uid)
      return user
    end

    seed = email.split("@").first.presence || auth.info.name
    create(
      provider: auth.provider,
      uid: auth.uid,
      email: email,
      full_name: auth.info.name.presence || email.split("@").first,
      username: generate_username(seed),
      password: Devise.friendly_token[0, 20]
    )
  rescue ActiveRecord::RecordNotUnique
    # Concurrent first sign-in: the other request won the unique [provider, uid]
    # index. Return the now-existing record.
    find_by(provider: auth.provider, uid: auth.uid)
  end

  # Derive a valid, unique username from a seed (email local-part or name). Strips to the
  # allowed [a-z0-9_] charset, guards RESERVED_USERNAMES, and appends an incrementing
  # numeric suffix until it lands on a free, non-reserved candidate.
  def self.generate_username(seed)
    base = seed.to_s.downcase.gsub(/[^a-z0-9_]/, "")[0, 30]
    base = "user" if base.blank? || RESERVED_USERNAMES.include?(base)
    candidate = base
    n = 1
    while exists?(username: candidate) || RESERVED_USERNAMES.include?(candidate)
      n += 1
      candidate = "#{base}#{n}"
    end
    candidate
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
    # Moderation: E6 sweep — the profile Hoojahs tab (HTML + API UserSerializer)
    # never lists removed claims.
    base.not_removed.where(parent_id: nil).includes(user: {avatar_attachment: :blob}).order(updated_at: :desc)
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

  # Gates the controller `update` path (`valid?`/`save`). A direct `avatar.attach` on a
  # persisted record bypasses this by design — attach writes immediately without validation.
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
