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
      expect(mail.subject).to eq("@#{mentioner.username} mentioned you on Hoojah")
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
      # Real Debate#notify rows carry BOTH the debated claim and the debate.
      notification = create(:notification, category: :debate_your_turn,
        user: recipient, subject_user: nil, hujah: debate.hujah, debate: debate)

      mail = NotificationMailer.with(notification: notification).notification_email

      expect(mail.body.encoded).to include("/debates/#{debate.slug}")
      expect(mail.body.encoded).not_to include("/hoojah/#{debate.hujah.slug}")
    end

    it "links a row produced by the debate model to the debate, not the claim" do
      debate = create(:debate)
      notification = Notification.where(category: :debate_challenge, debate_id: debate.id).last

      mail = NotificationMailer.with(notification: notification).notification_email

      expect(mail.body.encoded).to include("/debates/#{debate.slug}")
      expect(mail.body.encoded).not_to include("/hoojah/#{debate.hujah.slug}")
    end

    it "never puts a free-text full_name in the subject" do
      mentioner = create(:user, full_name: "Hoojah Support")
      notification = create(:notification, category: :mention,
        user: create(:user), subject_user: mentioner, hujah: create(:hujah))

      mail = NotificationMailer.with(notification: notification).notification_email

      expect(mail.subject).not_to include("Hoojah Support")
    end

    it "sends nothing when the recipient switched email off before the job ran" do
      recipient = create(:user)
      notification = create(:notification, category: :mention, user: recipient)
      recipient.update_columns(email_notifications: false)

      mail = NotificationMailer.with(notification: notification.reload).notification_email

      expect(mail.to).to be_blank
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
