require "rails_helper"

RSpec.describe ModerationPolicy do
  let(:member) { create(:user) }
  let(:moderator) { create(:user, :moderator) }
  let(:admin) { create(:user, :admin) }

  # Headless policy: instantiated with the :moderation symbol (no per-record nuance),
  # exactly the way ApplicationController's `authorize :moderation, :<action>?` resolves it.
  %i[index? dismiss? remove? warn?].each do |action|
    describe "##{action}" do
      it "denies an anonymous (nil) user" do
        expect(described_class.new(nil, :moderation).public_send(action)).to be(false)
      end

      it "denies a plain member" do
        expect(described_class.new(member, :moderation).public_send(action)).to be(false)
      end

      it "allows a moderator" do
        expect(described_class.new(moderator, :moderation).public_send(action)).to be(true)
      end

      it "allows an admin" do
        expect(described_class.new(admin, :moderation).public_send(action)).to be(true)
      end
    end
  end
end
