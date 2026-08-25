require "rails_helper"

RSpec.describe "Visibility", type: :model do
  let(:owner) { create(:user, private: true) }
  let(:follower) { create(:user) }
  let(:stranger) { create(:user) }
  before { follower.active_follows.create!(followed: owner, status: :accepted) }

  it "visible_to? — private: self + accepted follower only" do
    expect(owner.visible_to?(owner)).to be(true)
    expect(owner.visible_to?(follower)).to be(true)
    expect(owner.visible_to?(stranger)).to be(false)
    expect(owner.visible_to?(nil)).to be(false)
    expect(create(:user).visible_to?(stranger)).to be(true) # public
  end

  it "pending requester is NOT visible" do
    req = create(:user)
    req.active_follows.create!(followed: owner, status: :pending)
    expect(owner.visible_to?(req)).to be(false)
  end

  it "following/followers count accepted only" do
    p = create(:user)
    p.active_follows.create!(followed: owner, status: :pending)
    expect(owner.followers).to include(follower)
    expect(owner.followers).not_to include(p)
  end

  # Moderation (2026): removed content is staff-only EVERYWHERE — including its
  # author, who learns via the moderation_removed notification instead. The gate is
  # the FIRST line of Hujah#visible_to?, so it fires before the parent-recursion
  # branch — a removed REPLY is gated on its own status, not just its parent's.
  describe "Hujah#visible_to? — moderation gate" do
    let(:author) { create(:user, private: false) }
    let(:member) { create(:user) }
    let(:moderator) { create(:user, :moderator) }
    let(:admin) { create(:user, :admin) }

    context "a removed top-level hoojah" do
      let(:hujah) { create(:hujah, user: author, visibility: :visible_public) }
      before { hujah.update!(moderation_status: :removed) }

      it "is staff-only — hidden from anonymous, members, and even its author" do
        expect(hujah.visible_to?(nil)).to be(false)
        expect(hujah.visible_to?(member)).to be(false)
        expect(hujah.visible_to?(author)).to be(false)
        expect(hujah.visible_to?(moderator)).to be(true)
        expect(hujah.visible_to?(admin)).to be(true)
      end
    end

    context "a removed reply under an active public parent" do
      let(:parent) { create(:hujah, user: author, visibility: :visible_public) }
      let(:reply) { create(:hujah, user: author, parent: parent) }
      before { reply.update!(moderation_status: :removed) }

      it "is staff-only — proving the gate fires before parent recursion" do
        expect(reply.visible_to?(member)).to be(false)
        expect(reply.visible_to?(author)).to be(false)
        expect(reply.visible_to?(moderator)).to be(true)
      end
    end

    context "an active reply under a removed parent" do
      let(:parent) { create(:hujah, user: author, visibility: :visible_public) }
      let(:reply) { create(:hujah, user: author, parent: parent) }
      before { parent.update!(moderation_status: :removed) }

      it "is hidden from members (parent recursion) but visible to staff" do
        expect(reply.visible_to?(member)).to be(false)
        expect(reply.visible_to?(moderator)).to be(true)
      end
    end

    it "leaves an active public hoojah's visibility unchanged (regression guard)" do
      hujah = create(:hujah, user: author, visibility: :visible_public)
      expect(hujah.visible_to?(nil)).to be(true)
      expect(hujah.visible_to?(member)).to be(true)
      expect(hujah.visible_to?(author)).to be(true)
    end
  end
end
