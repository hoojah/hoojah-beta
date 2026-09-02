require "rails_helper"

RSpec.describe Notification, type: :model do
  include ActiveJob::TestHelper

  describe "the category enum" do
    # `category` is a plain integer column with existing rows, so the integers are
    # the contract — renumbering or reordering these reinterprets history.
    it "maps all seventeen categories to stable integers" do
      expect(Notification.categories).to eq(
        "admin" => 0,
        "announcement" => 1,
        "flag" => 2,
        "new_hoojah_response" => 3,
        "new_vote" => 4,
        "mention" => 5,
        "new_follower" => 6,
        "debate_challenge" => 7,
        "debate_declined" => 8,
        "debate_your_turn" => 9,
        "debate_concluded" => 10,
        "badge_earned" => 11,
        "follow_request" => 12,
        "follow_accepted" => 13,
        "moderation_removed" => 14,
        "moderation_warning" => 15,
        "hujah_archived" => 16
      )
    end

    # Slice 2 (editable-hujah): the purge notification. Integer 16 is the next free
    # value; like every category the integer is the contract, not the symbol.
    it "supports the hujah_archived category at integer 16" do
      expect(Notification.categories["hujah_archived"]).to eq(16)
    end

    it "does not email the hujah_archived category (in-app only)" do
      expect(Notification::EMAILED_CATEGORIES).not_to include("hujah_archived")
    end

    # Moderation (2026): the exact integers are load-bearing — the legacy API
    # serializes the category as its integer, so renumbering reinterprets rows.
    it "assigns the two moderation categories the next free integers" do
      expect(Notification.categories["moderation_removed"]).to eq(14)
      expect(Notification.categories["moderation_warning"]).to eq(15)
    end

    it "refuses a category outside the enum" do
      expect { create(:notification, category: :telepathy) }.to raise_error(ArgumentError)
    end
  end

  describe "associations" do
    it "requires a recipient" do
      notification = build(:notification, user: nil)
      expect(notification).not_to be_valid
      expect(notification.errors[:user]).to be_present
    end

    # hujah / subject_user / debate are all `optional: true` because the fourteen
    # categories carry different payloads: an `announcement` has no subject at all,
    # a `new_follower` has no hoojah, a `debate_*` has no hoojah, and `new_vote`
    # deliberately has no subject_user (see the secret-ballot example below).
    it "allows every subject association to be absent" do
      notification = build(:notification, category: :announcement,
        hujah: nil, subject_user: nil, debate: nil)
      expect(notification).to be_valid
    end

    it "declares hujah, subject_user and debate optional" do
      %i[hujah subject_user debate].each do |name|
        expect(Notification.reflect_on_association(name).options[:optional])
          .to be(true), "expected belongs_to :#{name} to stay optional"
      end
    end
  end

  # THE secret-ballot guard. Votes on a hoojah are effectively anonymous: the owner
  # is told THAT someone voted, never who. Recording the voter in subject_user_id
  # let the owner de-anonymize them straight out of NotificationSerializer (Slice 5,
  # Part A). Hujah#cast_vote is the producer and asserts its own side; this is the
  # model-side half — `optional: true` on subject_user is precisely what lets a
  # new_vote row exist with no voter recorded. Make that association required while
  # "tidying" and the secret ballot breaks silently, at the far end of the app.
  describe "a new_vote notification (secret ballot)" do
    let(:owner) { create(:user) }
    let(:hujah) { create(:hujah, user: owner) }

    it "is valid with no subject_user" do
      notification = build(:notification, user: owner, hujah: hujah,
        category: :new_vote, subject_user: nil)

      expect(notification).to be_valid
      expect(notification.save).to be(true)
      expect(notification.reload.subject_user_id).to be_nil
    end

    it "is `optional: true` on subject_user that permits it" do
      expect(Notification.reflect_on_association(:subject_user).options[:optional]).to be(true)
    end

    it "is what cast_vote actually writes — no voter recorded" do
      voter = create(:user)
      hujah.cast_vote(by: voter, choice: 1)

      notification = Notification.where(category: :new_vote, hujah_id: hujah.id).sole
      expect(notification.user_id).to eq(owner.id)
      expect(notification.subject_user_id).to be_nil
    end
  end

  describe ".unread" do
    # Load-bearing: User#unread_notifications_count drives the navbar badge.
    let(:user) { create(:user) }
    let!(:unread) { create(:notification, user: user, read: false) }
    let!(:read) { create(:notification, user: user, read: true) }

    it "returns only the unread notifications" do
      # Scoped to `user`: building a hoojah awards its author a first_hoojah badge,
      # which is itself an unread notification for a different user.
      expect(user.notifications.unread).to contain_exactly(unread)
      expect(Notification.unread).not_to include(read)
    end

    it "backs User#unread_notifications_count" do
      expect(user.unread_notifications_count).to eq(1)
      unread.update!(read: true)
      expect(user.reload.unread_notifications_count).to eq(0)
    end

    it "treats a freshly created notification as unread by default" do
      fresh = Notification.create!(user: user, category: :announcement)
      expect(fresh.read).to be(false)
      expect(Notification.unread).to include(fresh)
    end
  end

  # Issue #3: a single choke-point (`after_create_commit`) enqueues one email per
  # high-signal notification, so none of the ~10 Notification.create! call sites
  # change and a double-send is structurally impossible.
  describe "email delivery" do
    # (a) A high-signal category (mention) enqueues the mailer.
    it "enqueues NotificationMailer#notification_email for a mention" do
      expect {
        create(:notification, category: :mention)
      }.to have_enqueued_mail(NotificationMailer, :notification_email)
    end

    # (b) new_vote is EXCLUDED (secret ballot: the row has no subject_user_id, and
    # emailing per vote is spam), so it enqueues nothing.
    it "enqueues nothing for new_vote" do
      owner = create(:user)
      hujah = create(:hujah, user: owner)
      expect {
        create(:notification, category: :new_vote, user: owner, hujah: hujah, subject_user: nil)
      }.not_to have_enqueued_mail(NotificationMailer, :notification_email)
    end

    # (c) A recipient who has turned email off gets nothing.
    it "enqueues nothing when the recipient disabled email notifications" do
      recipient = create(:user, email_notifications: false)
      expect {
        create(:notification, category: :mention, user: recipient)
      }.not_to have_enqueued_mail(NotificationMailer, :notification_email)
    end

    # (d) after_create_commit (NOT after_create): a row created inside a
    # transaction that rolls back must never enqueue a job. new_vote / counter
    # writes run inside cast_vote's transaction, so this invariant is load-bearing.
    it "enqueues nothing for a notification whose transaction rolls back" do
      recipient = create(:user)
      expect {
        ActiveRecord::Base.transaction do
          Notification.create!(user: recipient, category: :mention)
          raise ActiveRecord::Rollback
        end
      }.not_to have_enqueued_mail(NotificationMailer, :notification_email)
    end
  end
end
