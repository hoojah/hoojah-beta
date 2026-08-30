require "rails_helper"

RSpec.describe NotificationMailer, type: :mailer do
  describe "#notification_email" do
    # (e) A mention email is addressed to the mentioned user, its subject names the
    # mentioner, and its body deep-links to the hoojah by slug.
    it "addresses the mentioned user, names the mentioner, and links the hoojah" do
      mentioner = create(:user, full_name: "Aisha Rahman")
      recipient = create(:user)
      hujah = create(:hujah)
      notification = create(:notification, category: :mention,
        user: recipient, subject_user: mentioner, hujah: hujah)

      mail = NotificationMailer.with(notification: notification).notification_email

      expect(mail.to).to eq([recipient.email])
      expect(mail.subject).to include("Aisha Rahman")
      expect(mail.body.encoded).to include(hujah.slug)
    end

    # (f) Moderation emails must preserve the same anonymity the Notification row
    # enforces (no subject_user_id): the body must NOT name the acting moderator.
    it "does not name the acting moderator in a moderation_removed email" do
      moderator = create(:user, :moderator, full_name: "Mod Nurul", username: "mod_nurul")
      recipient = create(:user)
      hujah = create(:hujah, user: recipient)
      # The real moderation_removed row carries no subject_user_id.
      notification = create(:notification, category: :moderation_removed,
        user: recipient, subject_user: nil, hujah: hujah)

      mail = NotificationMailer.with(notification: notification).notification_email

      expect(mail.body.encoded).not_to include(moderator.username)
      expect(mail.body.encoded).not_to include(moderator.full_name)
    end

    # (g) A debate_your_turn email deep-links to the debate by slug.
    it "deep-links to the debate for debate_your_turn" do
      recipient = create(:user)
      debate = create(:debate)
      notification = create(:notification, category: :debate_your_turn,
        user: recipient, subject_user: nil, hujah: nil, debate: debate)

      mail = NotificationMailer.with(notification: notification).notification_email

      expect(mail.body.encoded).to include(debate.slug)
      expect(mail.body.encoded).to include("/debates/")
    end

    # Guard: a recipient without an email address yields a no-op (nil) message body
    # rather than raising.
    it "no-ops cleanly when the recipient has no email" do
      recipient = create(:user)
      recipient.update_columns(email: "")
      notification = create(:notification, category: :mention, user: recipient)

      mail = NotificationMailer.with(notification: notification).notification_email

      expect(mail.to).to be_blank
    end
  end
end
