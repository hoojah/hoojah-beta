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
end
