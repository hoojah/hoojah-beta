class User < ApplicationRecord
  has_many :hujahs, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :flags, dependent: :destroy

  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable

  before_validation { self.email = email.to_s.downcase.strip }

  validates :full_name, presence: true
  validates :username, presence: true, uniqueness: true, length: {minimum: 1}

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
    notifications.where(read: false).count
  end

  private

  def assign_random_photo
    update_column(:photo, User.random_photo) if photo.blank?
  end
end
