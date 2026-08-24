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
end
