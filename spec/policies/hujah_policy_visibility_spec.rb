require "rails_helper"

RSpec.describe HujahPolicy do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }

  describe "#change_visibility?" do
    it "allows the owner of a top-level, active hoojah" do
      h = create(:hujah, user: owner)
      expect(HujahPolicy.new(owner, h).change_visibility?).to be(true)
    end

    it "denies a non-owner" do
      h = create(:hujah, user: owner)
      expect(HujahPolicy.new(other, h).change_visibility?).to be(false)
    end

    it "denies on a reply (not top-level)" do
      parent = create(:hujah, user: owner)
      reply = create(:hujah, user: owner, parent_id: parent.id, body: "A reply hoojah here")
      expect(HujahPolicy.new(owner, reply).change_visibility?).to be(false)
    end

    it "denies on a removed hoojah" do
      h = create(:hujah, user: owner, moderation_status: :removed)
      expect(HujahPolicy.new(owner, h).change_visibility?).to be(false)
    end
  end

  describe "#promote?" do
    it "allows the owner of a child (reply)" do
      parent = create(:hujah, user: owner)
      reply = create(:hujah, user: owner, parent_id: parent.id, body: "A reply hoojah here")
      expect(HujahPolicy.new(owner, reply).promote?).to be(true)
    end

    it "denies on a top-level hoojah (nothing to promote)" do
      h = create(:hujah, user: owner)
      expect(HujahPolicy.new(owner, h).promote?).to be(false)
    end

    it "denies a non-owner and a removed reply" do
      parent = create(:hujah, user: owner)
      reply = create(:hujah, user: owner, parent_id: parent.id, body: "A reply hoojah here")
      expect(HujahPolicy.new(other, reply).promote?).to be(false)
      reply.update!(moderation_status: :removed)
      expect(HujahPolicy.new(owner, reply).promote?).to be(false)
    end
  end
end
