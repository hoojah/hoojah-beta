require "rails_helper"

RSpec.describe HujahPolicy do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  let(:hujah) { create(:hujah, user: owner) }

  it "permits destroy only for the owner" do
    expect(HujahPolicy.new(owner, hujah).destroy?).to be(true)
    expect(HujahPolicy.new(other, hujah).destroy?).to be(false)
    expect(HujahPolicy.new(nil, hujah).destroy?).to be(false)
  end

  it "permits vote/create for any logged-in user" do
    expect(HujahPolicy.new(owner, hujah).vote?).to be(true)
    expect(HujahPolicy.new(nil, hujah).vote?).to be(false)
    expect(HujahPolicy.new(owner, hujah).create?).to be(true)
    expect(HujahPolicy.new(nil, hujah).create?).to be(false)
  end

  # ── Vote-to-respond gate (2026): a reply requires a prior vote on the parent ─────
  describe "vote-to-respond gate on create?" do
    it "forbids a reply before the replier has voted on the parent, allows it after" do
      parent = create(:hujah)
      replier = create(:user)
      reply = build(:hujah, parent: parent, user: replier)
      expect(HujahPolicy.new(replier, reply).create?).to be false
      parent.cast_vote(by: replier, choice: 1)
      expect(HujahPolicy.new(replier, reply).create?).to be true
    end
  end

  # ── Per-post visibility (2026): show? and vote? gate through visible_to? ─────────
  describe "per-post visibility on show?/vote?" do
    let(:stranger) { create(:user) }

    it "forbids a stranger from reading OR voting on a followers_only claim" do
      claim = create(:hujah, user: owner, visibility: :followers_only)
      expect(HujahPolicy.new(stranger, claim).show?).to be(false)
      expect(HujahPolicy.new(stranger, claim).vote?).to be(false)
      expect(HujahPolicy.new(nil, claim).show?).to be(false)
    end

    it "forbids a stranger from reading OR voting on a private_only claim, but allows the author" do
      claim = create(:hujah, user: owner, visibility: :private_only)
      expect(HujahPolicy.new(stranger, claim).show?).to be(false)
      expect(HujahPolicy.new(stranger, claim).vote?).to be(false)
      expect(HujahPolicy.new(owner, claim).show?).to be(true)
      expect(HujahPolicy.new(owner, claim).vote?).to be(true)
    end
  end

  # ── Block gate on vote? (2026): mirror create?'s block check ─────────────────────
  # A public hoojah is readable via visible_to?, but a blocker/blocked-by must not be
  # able to vote on its author — voting bumps the denormalized counters and is an
  # interaction the block is meant to prevent (create? already gated this).
  describe "block gate on vote?" do
    it "forbids a voter who has blocked the author" do
      voter = create(:user)
      create(:block, blocker: voter, blocked: owner)
      expect(HujahPolicy.new(voter, hujah).vote?).to be(false)
    end

    it "forbids a voter who is blocked BY the author (bidirectional)" do
      voter = create(:user)
      create(:block, blocker: owner, blocked: voter)
      expect(HujahPolicy.new(voter, hujah).vote?).to be(false)
    end

    it "still permits an unrelated signed-in user to vote" do
      expect(HujahPolicy.new(other, hujah).vote?).to be(true)
    end
  end

  # ── Slice 1 body edit: owner + not-removed + within the edit window ──────────────
  describe "edit?/update? (body edit window)" do
    it "permits the owner to edit a fresh, active, conviction-free hoojah" do
      h = create(:hujah, user: owner)
      expect(HujahPolicy.new(owner, h).edit?).to be(true)
      expect(HujahPolicy.new(owner, h).update?).to be(true)
    end

    it "forbids a non-owner and an anonymous viewer" do
      h = create(:hujah, user: owner)
      expect(HujahPolicy.new(other, h).edit?).to be(false)
      expect(HujahPolicy.new(nil, h).edit?).to be(false)
      expect(HujahPolicy.new(other, h).update?).to be(false)
    end

    it "forbids the owner once the 15-minute window has passed" do
      h = create(:hujah, user: owner, created_at: 16.minutes.ago)
      expect(HujahPolicy.new(owner, h).edit?).to be(false)
      expect(HujahPolicy.new(owner, h).update?).to be(false)
    end

    it "forbids the owner once a conviction has been cast" do
      h = create(:hujah, user: owner, conviction_count: 1)
      expect(HujahPolicy.new(owner, h).edit?).to be(false)
    end

    it "forbids editing a moderator-removed hoojah even for the owner" do
      h = create(:hujah, user: owner, moderation_status: :removed)
      expect(HujahPolicy.new(owner, h).edit?).to be(false)
    end
  end
end
