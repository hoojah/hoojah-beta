require "rails_helper"

RSpec.describe Hujah, type: :model do
  describe "new-record defaults" do
    it "defaults to visible_public, allow_debates true, conviction_count 0" do
      h = Hujah.new
      expect(h.visibility_visible_public?).to be true
      expect(h.allow_debates).to be true
      expect(h.conviction_count).to eq 0
    end
  end

  describe "body length + #voted_by?" do
    it "requires >= 8 chars for a top-level claim" do
      h = build(:hujah, parent: nil, body: "short")
      expect(h).not_to be_valid
    end

    it "allows a short reply" do
      parent = create(:hujah)
      h = build(:hujah, parent: parent, body: "ok")
      expect(h).to be_valid
    end

    it "voted_by? reflects a cast vote" do
      h = create(:hujah)
      u = create(:user)
      expect(h.voted_by?(u)).to be false
      h.cast_vote(by: u, choice: 1)
      expect(h.voted_by?(u)).to be true
    end
  end

  describe "#cast_vote conviction" do
    let(:h) { create(:hujah) }
    let(:u) { create(:user) }

    it "locks a conviction vote and refuses later changes" do
      h.cast_vote(by: u, choice: 1, conviction: true)
      expect(h.reload.conviction_count).to eq 1
      h.cast_vote(by: u, choice: 3) # attempt to switch
      expect(h.votes.find_by(user: u).vote.last).to eq 1 # unchanged
      expect(h.reload.agree_count).to eq 1
      expect(h.disagree_count).to eq 0
    end

    it "counts a conviction vote as exactly 1 toward its stance" do
      h.cast_vote(by: u, choice: 2, conviction: true)
      expect(h.reload.neutral_count).to eq 1
    end

    it "upgrades an existing non-conviction vote to conviction without double-counting" do
      h.cast_vote(by: u, choice: 1)
      h.cast_vote(by: u, choice: 1, conviction: true) # same stance, now lock it
      expect(h.reload.agree_count).to eq 1
      expect(h.conviction_count).to eq 1
      expect(h.votes.find_by(user: u).conviction).to be true
    end
  end

  describe "#visible_to? per-post" do
    let(:author) { create(:user) }
    let(:follower) { create(:user) }
    let(:stranger) { create(:user) }
    before { follower.active_follows.create!(followed: author, status: :accepted) }

    it "private_only claim: author only" do
      h = create(:hujah, user: author, visibility: :private_only)
      expect(h.visible_to?(author)).to be true
      expect(h.visible_to?(follower)).to be false
      expect(h.visible_to?(stranger)).to be false
      expect(h.visible_to?(nil)).to be false
    end

    it "followers_only claim: author + accepted followers, not strangers" do
      h = create(:hujah, user: author, visibility: :followers_only)
      expect(h.visible_to?(author)).to be true
      expect(h.visible_to?(follower)).to be true
      expect(h.visible_to?(stranger)).to be false
      expect(h.visible_to?(nil)).to be false
    end

    it "visible_public claim by a public author: everyone" do
      h = create(:hujah, user: author, visibility: :visible_public)
      expect(h.visible_to?(stranger)).to be true
      expect(h.visible_to?(nil)).to be true
    end

    # Slice 7b Gate 6 regression guard: a PRIVATE replier's reply under a public
    # parent must stay hidden from a stranger, visible to an accepted follower.
    it "a private replier's reply under a public parent is gated by the replier's own privacy" do
      private_replier = create(:user, private: true)
      fan = create(:user)
      fan.active_follows.create!(followed: private_replier, status: :accepted)
      parent = create(:hujah, user: author, visibility: :visible_public)
      reply = create(:hujah, parent: parent, user: private_replier, body: "a reply body")
      expect(reply.visible_to?(stranger)).to be false
      expect(reply.visible_to?(fan)).to be true
      expect(reply.visible_to?(private_replier)).to be true
    end
  end

  describe "#current_user_vote" do
    let!(:user) { create(:user) }
    let!(:hujah) { create(:hujah) }
    context "if logged in without voting" do
      it "will return nil" do
        result = hujah.current_user_vote(logged_in: true, current_user_id: user.id)
        expect(result).to eq(nil)
      end
    end

    context "if logged in and has voted" do
      let!(:vote) { create(:vote, :agree, user: user, hujah: hujah) }
      it "will return vote value" do
        result = hujah.current_user_vote(logged_in: true, current_user_id: user.id)
        expect(result).to eq("agree")
      end
    end

    context "if not logged in" do
      it "will return nil" do
        result = hujah.current_user_vote(logged_in: false, current_user_id: nil)
        expect(result).to eq(nil)
      end
    end
  end
end
