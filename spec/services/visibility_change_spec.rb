require "rails_helper"

RSpec.describe VisibilityChange do
  let(:author) { create(:user, username: "author") }
  let(:follower) { create(:user, username: "follower") }
  let(:stranger) { create(:user, username: "stranger") }

  def accept_follow(from:, to:)
    from.active_follows.create!(followed: to, status: :accepted)
  end

  describe "direction" do
    it "classifies tightening / loosening / no-op by enum rank" do
      h = create(:hujah, user: author, visibility: :followers_only)
      expect(VisibilityChange.new(h, to: "private_only")).to be_tightening
      expect(VisibilityChange.new(h, to: "visible_public")).to be_loosening
      expect(VisibilityChange.new(h, to: "followers_only")).to be_no_op
    end
  end

  describe "#affected_participants (public -> followers_only)" do
    it "affects a voting stranger but not an accepted follower or the author" do
      h = create(:hujah, user: author, visibility: :visible_public)
      accept_follow(from: follower, to: author)
      h.cast_vote(by: follower, choice: 1)
      h.cast_vote(by: stranger, choice: 3)

      change = VisibilityChange.new(h, to: "followers_only")
      ids = change.affected_participants.map(&:id)
      expect(ids).to contain_exactly(stranger.id)
    end
  end

  describe "#affected_participants (public -> private_only)" do
    it "affects every non-author participant, incl. a subtree argument author" do
      h = create(:hujah, user: author, visibility: :visible_public)
      accept_follow(from: follower, to: author)
      h.cast_vote(by: follower, choice: 1)
      h.cast_vote(by: stranger, choice: 2)
      arg_author = create(:user, username: "argauthor")
      h.cast_vote(by: arg_author, choice: 1)
      create(:hujah, user: arg_author, parent_id: h.id, body: "A subtree argument")

      change = VisibilityChange.new(h, to: "private_only")
      expect(change.affected_participants.map(&:id))
        .to contain_exactly(follower.id, stranger.id, arg_author.id)
    end
  end

  describe "#counts" do
    it "reports users / votes / arguments to be removed" do
      h = create(:hujah, user: author, visibility: :visible_public)
      h.cast_vote(by: stranger, choice: 1)
      create(:hujah, user: stranger, parent_id: h.id, body: "Strangers argument here")

      counts = VisibilityChange.new(h, to: "private_only").counts
      expect(counts).to eq(users: 1, votes: 1, arguments: 1)
    end
  end

  describe "#blockers (entanglement, fail closed)" do
    let(:author) { create(:user, username: "author") }
    let(:stranger) { create(:user, username: "stranger") }
    let(:other) { create(:user, username: "other") }

    def public_hujah = create(:hujah, user: author, visibility: :visible_public)

    it "is empty when an affected arg is a clean leaf (no others' replies/votes/debate)" do
      h = public_hujah
      h.cast_vote(by: stranger, choice: 1)
      create(:hujah, user: stranger, parent_id: h.id, body: "A lonely argument here")
      expect(VisibilityChange.new(h, to: "private_only").blockers).to be_empty
    end

    it "blocks when an affected arg has a reply from ANOTHER user" do
      h = public_hujah
      h.cast_vote(by: stranger, choice: 1)
      arg = create(:hujah, user: stranger, parent_id: h.id, body: "An argument with a reply")
      create(:hujah, user: other, parent_id: arg.id, body: "Someone elses reply here")

      blockers = VisibilityChange.new(h, to: "private_only").blockers
      expect(blockers.map(&:id)).to contain_exactly(arg.id)
    end

    it "blocks when an affected arg has a vote from ANOTHER user" do
      h = public_hujah
      h.cast_vote(by: stranger, choice: 1)
      arg = create(:hujah, user: stranger, parent_id: h.id, body: "An argument with a vote")
      arg.cast_vote(by: other, choice: 2)

      expect(VisibilityChange.new(h, to: "private_only").blockers.map(&:id))
        .to contain_exactly(arg.id)
    end

    it "blocks when an affected arg is attached to a debate" do
      h = public_hujah
      h.cast_vote(by: stranger, choice: 1)
      arg = create(:hujah, user: stranger, parent_id: h.id, body: "An argument in a debate")
      create(:debate, hujah: arg, challenger: stranger, opponent: other, status: :active)

      expect(VisibilityChange.new(h, to: "private_only").blockers.map(&:id))
        .to contain_exactly(arg.id)
    end
  end
end
