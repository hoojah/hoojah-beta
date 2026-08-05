class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :hujah, optional: true
  belongs_to :subject_user, class_name: "User", optional: true
  belongs_to :debate, optional: true

  enum :category, {
    admin: 0,
    announcement: 1,
    flag: 2,
    new_hoojah_response: 3,
    new_vote: 4,
    mention: 5,
    new_follower: 6,
    debate_challenge: 7,
    debate_declined: 8,
    debate_your_turn: 9,
    debate_concluded: 10,
    badge_earned: 11,
    follow_request: 12,
    follow_accepted: 13
  }

  scope :unread, -> { where(read: false) }
end
