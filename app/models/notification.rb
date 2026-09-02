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
    follow_accepted: 13,
    # Moderation (2026): author-facing. Exact integers are load-bearing — the legacy
    # API serializes the category as its integer.
    moderation_removed: 14,
    moderation_warning: 15,
    # Slice 2 (editable-hujah): sent to a participant whose votes/arguments were
    # purged when the author tightened this hoojah's visibility. FK-less hujah_id
    # (like every category here) so it survives the hoojah's later deletion. NOT in
    # EMAILED_CATEGORIES — a purge is not a high-signal per-user email event.
    hujah_archived: 16
  }

  scope :unread, -> { where(read: false) }

  # Issue #3: the high-signal categories that trigger an email. Deliberately EXCLUDES
  # new_vote (secret ballot — the row carries no subject_user_id and per-vote email is
  # spam), new_hoojah_response, new_follower, follow_accepted, badge_earned, and the
  # legacy admin/announcement/flag categories.
  EMAILED_CATEGORIES = %w[
    mention
    debate_challenge
    debate_your_turn
    debate_declined
    debate_concluded
    moderation_removed
    moderation_warning
    follow_request
  ].freeze

  # after_create_commit (NOT after_create): new_vote and counter writes are created
  # inside Hujah#cast_vote's transaction, and a job must never enqueue for a row that
  # a rollback would erase. This single choke-point means none of the ~10
  # Notification.create! call sites need to know about email.
  after_create_commit :deliver_email_later

  private

  def deliver_email_later
    return unless EMAILED_CATEGORIES.include?(category)
    return unless user.email_notifications? && user.email.present?

    NotificationMailer.with(notification: self).notification_email.deliver_later
  end
end
