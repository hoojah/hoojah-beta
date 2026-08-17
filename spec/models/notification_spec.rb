require "rails_helper"

RSpec.describe Notification, type: :model do
  describe "the category enum" do
    # `category` is a plain integer column with existing rows, so the integers are
    # the contract — renumbering or reordering these reinterprets history.
    it "maps all fourteen categories to stable integers" do
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
        "follow_accepted" => 13
      )
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
end
