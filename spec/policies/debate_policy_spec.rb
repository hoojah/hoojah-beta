require "rails_helper"

RSpec.describe DebatePolicy do
  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }
  let(:stranger) { create(:user) }

  def debate(status:)
    create(:debate, challenger: challenger, opponent: opponent, status: status)
  end

  describe "#show?" do
    it "lets anyone (incl. a nil user) view a concluded debate" do
      d = debate(status: :concluded)
      expect(DebatePolicy.new(nil, d).show?).to be(true)
      expect(DebatePolicy.new(stranger, d).show?).to be(true)
      expect(DebatePolicy.new(challenger, d).show?).to be(true)
    end

    it "limits an active debate to its participants" do
      d = debate(status: :active)
      expect(DebatePolicy.new(challenger, d).show?).to be(true)
      expect(DebatePolicy.new(opponent, d).show?).to be(true)
      expect(DebatePolicy.new(stranger, d).show?).to be_falsey
      expect(DebatePolicy.new(nil, d).show?).to be_falsey
    end
  end

  describe "#create?" do
    it "forbids create when the hoojah disallows debates" do
      claim = create(:hujah, allow_debates: false)
      reply = create(:hujah, parent: claim, user: create(:user), body: "an argument reply")
      d = build(:debate, hujah: claim, opponent: reply.user, challenger: create(:user))
      expect(DebatePolicy.new(d.challenger, d).create?).to be false
    end

    it "permits create when the hoojah allows debates and the opponent isn't hidden" do
      claim = create(:hujah, allow_debates: true)
      reply = create(:hujah, parent: claim, user: create(:user), body: "an argument reply")
      d = build(:debate, hujah: claim, opponent: reply.user, challenger: create(:user))
      expect(DebatePolicy.new(d.challenger, d).create?).to be true
    end
  end

  # ── Per-post visibility (2026): a concluded debate on a non-public claim renders
  # that claim's body, so the non-participant transcript branch must also gate on it.
  describe "#show? — concluded transcript on a non-public claim" do
    it "hides a concluded debate whose claim is followers_only from a stranger" do
      restricted = create(:hujah, user: create(:user), visibility: :followers_only)
      d = create(:debate, hujah: restricted, challenger: challenger, opponent: opponent, status: :concluded)
      expect(DebatePolicy.new(stranger, d).show?).to be false
      expect(DebatePolicy.new(nil, d).show?).to be false
      # participants still see their own debate
      expect(DebatePolicy.new(challenger, d).show?).to be true
    end

    it "keeps a concluded debate on a public claim visible to a stranger" do
      d = create(:debate, challenger: challenger, opponent: opponent, status: :concluded)
      expect(DebatePolicy.new(stranger, d).show?).to be true
    end
  end

  describe "Scope — concluded set gates on claim visibility" do
    it "excludes a concluded debate on a followers_only claim for a stranger" do
      restricted = create(:hujah, user: create(:user), visibility: :followers_only)
      hidden = create(:debate, hujah: restricted, challenger: challenger, opponent: opponent, status: :concluded)
      visible = create(:debate, challenger: challenger, opponent: opponent, status: :concluded)
      resolved = DebatePolicy::Scope.new(stranger, Debate.all).resolve
      expect(resolved).to include(visible)
      expect(resolved).not_to include(hidden)
    end
  end

  describe "#accept? / #decline?" do
    it "permits only the opponent, and only while pending" do
      d = debate(status: :pending)
      expect(DebatePolicy.new(opponent, d).accept?).to be(true)
      expect(DebatePolicy.new(opponent, d).decline?).to be(true)
      expect(DebatePolicy.new(challenger, d).accept?).to be_falsey
      expect(DebatePolicy.new(stranger, d).decline?).to be_falsey
      expect(DebatePolicy.new(nil, d).accept?).to be_falsey
    end

    it "denies accept/decline once no longer pending" do
      d = debate(status: :active)
      expect(DebatePolicy.new(opponent, d).accept?).to be_falsey
      expect(DebatePolicy.new(opponent, d).decline?).to be_falsey
    end
  end

  describe "#conclude?" do
    it "permits either participant only while active" do
      active = debate(status: :active)
      expect(DebatePolicy.new(challenger, active).conclude?).to be(true)
      expect(DebatePolicy.new(opponent, active).conclude?).to be(true)
      expect(DebatePolicy.new(stranger, active).conclude?).to be_falsey
      expect(DebatePolicy.new(nil, active).conclude?).to be_falsey

      pending = debate(status: :pending)
      expect(DebatePolicy.new(challenger, pending).conclude?).to be_falsey
    end
  end

  describe "#extend?" do
    it "permits either participant only while active" do
      active = debate(status: :active)
      expect(DebatePolicy.new(challenger, active).extend?).to be(true)
      expect(DebatePolicy.new(opponent, active).extend?).to be(true)
      expect(DebatePolicy.new(stranger, active).extend?).to be_falsey
      expect(DebatePolicy.new(nil, active).extend?).to be_falsey

      %i[pending concluded declined].each do |status|
        expect(DebatePolicy.new(challenger, debate(status: status)).extend?).to be_falsey
      end
    end

    # DELIBERATE: the policy answers "is this actor a party to a live debate",
    # nothing finer. The closing-round window and the MAX_ROUNDS ceiling are
    # applicability, not authorization — extendable_by? owns them, and the
    # controller turns a false there into 422. A participant must never be told
    # "not allowed" for asking at the wrong moment.
    it "ignores the extension window and the ceiling — those are 422 conditions" do
      fresh = debate(status: :active) # zero turns: nowhere near the boundary
      at_ceiling = debate(status: :active)
      at_ceiling.update!(rounds_limit: Debate::MAX_ROUNDS)

      expect(DebatePolicy.new(challenger, fresh).extend?).to be(true)
      expect(DebatePolicy.new(challenger, at_ceiling).extend?).to be(true)
      expect(fresh.extendable_by?(challenger)).to be(false)
      expect(at_ceiling.extendable_by?(challenger)).to be(false)
    end
  end

  describe "Scope" do
    it "shows a nil user only concluded debates" do
      concluded = debate(status: :concluded)
      active = debate(status: :active)
      resolved = DebatePolicy::Scope.new(nil, Debate.all).resolve
      expect(resolved).to include(concluded)
      expect(resolved).not_to include(active)
    end

    it "shows a participant concluded debates plus their own, but not others' active" do
      concluded = debate(status: :concluded)
      mine_active = debate(status: :active)
      others_active = create(:debate, status: :active)

      resolved = DebatePolicy::Scope.new(challenger, Debate.all).resolve
      expect(resolved).to include(concluded, mine_active)
      expect(resolved).not_to include(others_active)
    end
  end
end
