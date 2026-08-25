require "rails_helper"

RSpec.describe Flag, type: :model do
  # This file was a `pending` stub for as long as spec/factories/flags.rb was
  # unrunnable generator scaffolding (`hoojah { nil }` — no such attribute — plus
  # two nil belongs_to). The factory is fixed; these are the invariants it guards.
  it "builds a valid flag from the factory" do
    expect(create(:flag)).to be_valid
  end

  describe "the subject enum" do
    # The integer values are the contract: `subject` is a plain integer column, so
    # renumbering these silently reinterprets every row already in the table.
    it "maps the three report reasons to stable integers" do
      expect(Flag.subjects).to eq("spam" => 0, "abusive" => 1, "irrelevant" => 2)
    end

    it "exposes each reason as a predicate and a scope" do
      spam = create(:flag, subject: :spam)
      abusive = create(:flag, subject: :abusive)

      expect(spam).to be_spam
      expect(spam).not_to be_abusive
      expect(Flag.abusive).to contain_exactly(abusive)
    end

    it "refuses a reason outside the enum" do
      expect { create(:flag, subject: :libellous) }.to raise_error(ArgumentError)
    end
  end

  describe "associations" do
    # Both are required (no `optional: true`): a flag with no reporter cannot be
    # acted on, and a flag with no target is not a report of anything.
    it "requires a user" do
      flag = build(:flag, user: nil)
      expect(flag).not_to be_valid
      expect(flag.errors[:user]).to be_present
    end

    it "requires a hujah" do
      flag = build(:flag, hujah: nil)
      expect(flag).not_to be_valid
      expect(flag.errors[:hujah]).to be_present
    end

    it "is destroyed with the hoojah it reports" do
      flag = create(:flag)
      expect { flag.hujah.destroy }.to change(Flag, :count).by(-1)
    end
  end

  # Moderation (2026): the review lifecycle. `status` integers are the contract (a
  # plain integer column), `resolve!` is the single audited transition, and the
  # unique index enforces one report per [user, hujah].
  describe "the status lifecycle" do
    it "maps the three states to stable integers" do
      expect(Flag.statuses).to eq("pending" => 0, "dismissed" => 1, "actioned" => 2)
    end

    it "defaults a new flag to pending" do
      expect(create(:flag)).to be_pending
    end

    it "exposes .pending returning only pending flags" do
      pending = create(:flag)
      resolved = create(:flag)
      resolved.update!(status: :dismissed)
      expect(Flag.pending).to contain_exactly(pending)
    end
  end

  describe "uniqueness of [user, hujah]" do
    it "rejects a second report by the same user on the same hoojah" do
      first = create(:flag)
      dup = build(:flag, user: first.user, hujah: first.hujah, subject: :abusive)
      expect(dup).not_to be_valid
      expect(dup.errors[:user_id]).to be_present
    end

    it "allows the same user to report a different hoojah" do
      first = create(:flag)
      other = build(:flag, user: first.user, hujah: create(:hujah))
      expect(other).to be_valid
    end
  end

  describe "#resolve!" do
    let(:moderator) { create(:user, :moderator) }

    it "records status, resolver, and timestamp in one write when dismissing" do
      flag = create(:flag)
      freeze_time do
        flag.resolve!(by: moderator, as: :dismissed)
        expect(flag.reload).to be_dismissed
        expect(flag.resolved_by).to eq(moderator)
        expect(flag.resolved_at).to eq(Time.current)
      end
    end

    it "records the actioned transition the same way" do
      flag = create(:flag)
      freeze_time do
        flag.resolve!(by: moderator, as: :actioned)
        expect(flag.reload).to be_actioned
        expect(flag.resolved_by).to eq(moderator)
        expect(flag.resolved_at).to eq(Time.current)
      end
    end
  end
end
