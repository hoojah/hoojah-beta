class User < ApplicationRecord
  has_many :hujahs, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :flags, dependent: :destroy

  # Follow graph. active_follows = follows I initiated (I am the follower);
  # passive_follows = follows pointed at me (I am the followed).
  has_many :active_follows, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :following, through: :active_follows, source: :followed
  has_many :passive_follows, class_name: "Follow", foreign_key: :followed_id, dependent: :destroy
  has_many :followers, through: :passive_follows, source: :follower

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

  def photo_from_cloudinary
    return if photo.blank?
    uri = URI.parse(photo)
    ok = uri.scheme == "https" && uri.host == "res.cloudinary.com" && uri.path.start_with?("/hoojah/")
    errors.add(:photo, "must be a Hoojah Cloudinary URL") unless ok
  rescue URI::InvalidURIError
    errors.add(:photo, "is not a valid URL")
  end

  private

  def assign_random_photo
    update_column(:photo, User.random_photo) if photo.blank?
  end
end
