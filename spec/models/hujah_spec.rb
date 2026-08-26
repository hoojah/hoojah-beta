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

  describe "secret-ballot k-anonymity (#total_votes / #breakdown_visible?)" do
    it "reuses UserAnalytics::K (== 5) as the single threshold source" do
      expect(UserAnalytics::K).to eq(5)
      expect(Hujah::VOTE_BREAKDOWN_MIN).to eq(UserAnalytics::K)
    end

    it "#total_votes sums the three denormalized stance counters" do
      h = build(:hujah, agree_count: 2, neutral_count: 1, disagree_count: 4)
      expect(h.total_votes).to eq(7)
    end

    it "#total_votes treats nil counters as zero" do
      h = build(:hujah, agree_count: nil, neutral_count: nil, disagree_count: nil)
      expect(h.total_votes).to eq(0)
    end

    it "#breakdown_visible? is false at 0 total votes" do
      h = build(:hujah, agree_count: 0, neutral_count: 0, disagree_count: 0)
      expect(h.breakdown_visible?).to be false
    end

    it "#breakdown_visible? is false at 4 total votes (below k)" do
      h = build(:hujah, agree_count: 2, neutral_count: 1, disagree_count: 1)
      expect(h.breakdown_visible?).to be false
    end

    it "#breakdown_visible? is true at exactly 5 total votes (the k boundary)" do
      h = build(:hujah, agree_count: 3, neutral_count: 1, disagree_count: 1)
      expect(h.breakdown_visible?).to be true
    end

    it "#breakdown_visible? is true above k" do
      h = build(:hujah, agree_count: 50, neutral_count: 20, disagree_count: 30)
      expect(h.breakdown_visible?).to be true
    end

    describe "#ballot_counts (single-source serializer gate)" do
      it "nils the three per-stance counts and keeps total_count below k" do
        h = build(:hujah, agree_count: 2, neutral_count: 1, disagree_count: 1) # total 4
        expect(h.ballot_counts).to eq(
          total_count: 4, agree_count: nil, neutral_count: nil, disagree_count: nil
        )
      end

      it "exposes the real per-stance counts and total at or above k" do
        h = build(:hujah, agree_count: 3, neutral_count: 1, disagree_count: 1) # total 5
        expect(h.ballot_counts).to eq(
          total_count: 5, agree_count: 3, neutral_count: 1, disagree_count: 1
        )
      end
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

    it "locks and counts a conviction vote cast on a DIFFERENT stance than the current vote" do
      h.cast_vote(by: u, choice: 1) # tapped agree (not locked)
      h.cast_vote(by: u, choice: 3, conviction: true) # hold-charge disagree → switch + lock
      expect(h.reload.disagree_count).to eq 1
      expect(h.agree_count).to eq 0
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

  # Canonical SQL visibility scope for LIST surfaces (search, Phase 2). Must match
  # Hujah#visible_to? exactly for TOP-LEVEL records only — replies are intentionally
  # excluded (see the scope's comment in app/models/hujah.rb).
  describe ".visible_to scope" do
    let(:public_author) { create(:user, private: false) }
    let(:private_author) { create(:user, private: true) }
    let(:viewer) { create(:user) }
    let(:follower_of_public) { create(:user) }
    let(:follower_of_private) { create(:user) }
    let(:stranger) { create(:user) }

    before do
      follower_of_public.active_follows.create!(followed: public_author, status: :accepted)
      follower_of_private.active_follows.create!(followed: private_author, status: :accepted)
    end

    it "includes a visible_public post by a public author" do
      h = create(:hujah, user: public_author, visibility: :visible_public)
      expect(Hujah.visible_to(viewer)).to include(h)
    end

    it "excludes a public author's followers_only post from a non-follower" do
      h = create(:hujah, user: public_author, visibility: :followers_only)
      expect(Hujah.visible_to(stranger)).not_to include(h)
    end

    it "excludes a public author's private_only post from a non-owner" do
      h = create(:hujah, user: public_author, visibility: :private_only)
      expect(Hujah.visible_to(stranger)).not_to include(h)
    end

    it "includes a public author's followers_only post for an accepted follower and the owner" do
      h = create(:hujah, user: public_author, visibility: :followers_only)
      expect(Hujah.visible_to(follower_of_public)).to include(h)
      expect(Hujah.visible_to(public_author)).to include(h)
    end

    it "excludes a private author's posts from a non-follower" do
      h = create(:hujah, user: private_author, visibility: :visible_public)
      expect(Hujah.visible_to(stranger)).not_to include(h)
    end

    it "includes a private author's posts for an accepted follower" do
      h = create(:hujah, user: private_author, visibility: :visible_public)
      expect(Hujah.visible_to(follower_of_private)).to include(h)
    end

    it "excludes posts by a user in viewer.hidden_user_ids (blocked or blocking)" do
      blocked_author = create(:user, private: false)
      h1 = create(:hujah, user: blocked_author, visibility: :visible_public)
      viewer.blocks_made.create!(blocked: blocked_author)

      blocker_author = create(:user, private: false)
      h2 = create(:hujah, user: blocker_author, visibility: :visible_public)
      blocker_author.blocks_made.create!(blocked: viewer)

      expect(Hujah.visible_to(viewer)).not_to include(h1)
      expect(Hujah.visible_to(viewer)).not_to include(h2)
    end

    it "returns only top-level rows -- a matching reply is excluded" do
      parent = create(:hujah, user: public_author, visibility: :visible_public)
      reply = create(:hujah, parent: parent, user: public_author, body: "a reply body")
      expect(Hujah.visible_to(viewer)).to include(parent)
      expect(Hujah.visible_to(viewer)).not_to include(reply)
    end

    context "anonymous viewer (nil)" do
      it "returns only visible_public posts by non-private authors" do
        h = create(:hujah, user: public_author, visibility: :visible_public)
        expect(Hujah.visible_to(nil)).to include(h)
      end

      it "excludes a followers_only post" do
        h = create(:hujah, user: public_author, visibility: :followers_only)
        expect(Hujah.visible_to(nil)).not_to include(h)
      end

      it "excludes any post by a private author" do
        h = create(:hujah, user: private_author, visibility: :visible_public)
        expect(Hujah.visible_to(nil)).not_to include(h)
      end
    end

    it "agrees with Hujah#visible_to? on a sample of top-level records" do
      samples = [
        create(:hujah, user: public_author, visibility: :visible_public),
        create(:hujah, user: public_author, visibility: :followers_only),
        create(:hujah, user: public_author, visibility: :private_only),
        create(:hujah, user: private_author, visibility: :visible_public),
        create(:hujah, user: private_author, visibility: :followers_only)
      ]
      [viewer, follower_of_public, follower_of_private, stranger, public_author, private_author, nil].each do |v|
        scoped_ids = Hujah.visible_to(v).pluck(:id)
        samples.each do |h|
          expect(scoped_ids.include?(h.id)).to eq(h.visible_to?(v)),
            "mismatch for hujah=#{h.id} viewer=#{v&.id.inspect} visibility=#{h.visibility}"
        end
      end
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

  describe "hashtag parsing" do
    it "extracts and links #tags on save, case-insensitively and idempotently" do
      h = create(:hujah, body: "Free transit for #KlangValley and #klangvalley please today")
      expect(h.hashtags.pluck(:name)).to contain_exactly("klangvalley")
      expect(h.hashtags.first.display).to eq "KlangValley"
      h.update!(body: "Now about #Belanjawan spending decisions here")
      expect(h.reload.hashtags.pluck(:name)).to contain_exactly("belanjawan")
    end

    it "does not treat a # inside a word as a tag" do
      h = create(:hujah, body: "The C#Sharp language is not a tag here")
      expect(h.hashtags).to be_empty
    end

    it "caps at 10 tags per hoojah" do
      body = "Big list " + (1..15).map { |n| "#tag#{n}" }.join(" ")
      h = create(:hujah, body: body)
      expect(h.hashtags.count).to eq 10
    end

    it "decrements a tag's counter when the tag is removed from the body" do
      h = create(:hujah, body: "Keep #alpha and #beta together here")
      alpha = Hashtag.find_by(name: "alpha")
      expect(alpha.reload.hujahs_count).to eq 1
      h.update!(body: "Only #beta remains in this claim now")
      expect(alpha.reload.hujahs_count).to eq 0
    end
  end

  # Every SQL SELECT the block issues against the `debates` table.
  def debate_selects
    seen = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      sql = ActiveSupport::Notifications::Event.new(*args).payload[:sql].to_s
      seen << sql if sql =~ /\ASELECT/i && sql =~ /\bdebates\b/i
    end
    yield
    seen
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe "#active_debate" do
    it "returns nil when the hoojah has no debates at all" do
      h = create(:hujah, parent_id: nil)
      expect(h.active_debate).to be_nil
    end

    it "falls back to a live lookup for the active debate, ignoring other statuses" do
      h = create(:hujah, parent_id: nil)
      create(:debate, hujah: h, status: :declined)
      active = create(:debate, hujah: h, status: :active)
      expect(h.active_debate).to eq(active)
    end

    it "returns nil off the feed when the only debate is pending, not active" do
      h = create(:hujah, parent_id: nil)
      create(:debate, hujah: h, status: :pending)
      expect(h.active_debate).to be_nil
    end

    it "returns the preloaded debate with no query once the controller has set it" do
      h = create(:hujah, parent_id: nil)
      active = create(:debate, hujah: h, status: :active)
      h.preloaded_active_debate = active

      result = nil
      selects = debate_selects { result = h.active_debate }

      expect(result).to eq(active)
      expect(selects).to be_empty
    end

    it "trusts an explicit preloaded nil rather than falling back to a live lookup" do
      h = create(:hujah, parent_id: nil)
      create(:debate, hujah: h, status: :active)
      h.preloaded_active_debate = nil # the controller preloaded and found none for this id

      result = :untouched
      selects = debate_selects { result = h.active_debate }

      expect(result).to be_nil
      expect(selects).to be_empty
    end
  end

  # Phase 2.2 search scope — reuses .visible_to (proven above) then filters by body.
  # These specs cover the ILIKE/sanitize behaviour; the visibility re-use itself is
  # leak-tested end-to-end in spec/requests/search_spec.rb.
  describe ".search" do
    let(:viewer) { create(:user) }

    it "matches a case-insensitive substring of the body" do
      h = create(:hujah, body: "Cheaper FARES on the MRT line please")
      expect(Hujah.search("fares", viewer: viewer)).to include(h)
    end

    it "excludes a non-matching body" do
      h = create(:hujah, body: "totally unrelated content here")
      expect(Hujah.search("zzz-no-match", viewer: viewer)).not_to include(h)
    end

    it "excludes a reply (parent_id present) even when the body matches" do
      parent = create(:hujah, body: "a parent claim body")
      reply = create(:hujah, parent: parent, body: "UNIQUEREPLYTERM in a reply")
      expect(Hujah.search("UNIQUEREPLYTERM", viewer: viewer)).not_to include(reply)
    end

    it "treats % and _ as literal characters, not SQL wildcards (sanitize_sql_like)" do
      literal = create(:hujah, body: "this claim literally contains a % percent sign")
      no_percent = create(:hujah, body: "totally unrelated content with no percent sign at all")
      results = Hujah.search("%", viewer: viewer)
      expect(results).to include(literal)
      expect(results).not_to include(no_percent)
    end

    it "caps results at 8" do
      9.times { |n| create(:hujah, body: "CAPTERM number #{n} in the body") }
      expect(Hujah.search("CAPTERM", viewer: viewer).size).to eq(8)
    end
  end

  # Moderation (2026): moderation_status is the single visibility-enforcement point.
  # The :moderation prefix keeps predicates clear of the visibility_* and debate
  # status enums.
  describe "moderation_status" do
    it "maps the two states to stable integers" do
      expect(Hujah.moderation_statuses).to eq("active" => 0, "removed" => 1)
    end

    it "defaults a new hoojah to moderation_active" do
      expect(create(:hujah)).to be_moderation_active
    end

    it "flips to moderation_removed on update" do
      h = create(:hujah)
      h.update!(moderation_status: :removed)
      expect(h).to be_moderation_removed
    end

    describe ".not_removed" do
      it "excludes removed records and includes active ones" do
        active = create(:hujah)
        removed = create(:hujah)
        removed.update!(moderation_status: :removed)
        expect(Hujah.not_removed).to include(active)
        expect(Hujah.not_removed).not_to include(removed)
      end
    end
  end

  describe "#visible_children_for" do
    let(:author) { create(:user) }
    let(:parent) { create(:hujah, user: author) }
    let(:viewer) { create(:user) }

    it "includes a public author's reply for anyone (incl. anonymous)" do
      child = create(:hujah, user: create(:user), parent: parent)
      expect(parent.visible_children_for(nil)).to include(child)
      expect(parent.visible_children_for(viewer)).to include(child)
    end

    it "hides a private author's reply from a stranger and from anonymous" do
      child = create(:hujah, user: create(:user, private: true), parent: parent)
      expect(parent.visible_children_for(nil)).not_to include(child)
      expect(parent.visible_children_for(viewer)).not_to include(child)
    end

    it "shows a private author's reply to an accepted follower and to the author" do
      priv = create(:user, private: true)
      child = create(:hujah, user: priv, parent: parent)
      priv.passive_follows.create!(follower: viewer, status: :accepted)
      expect(parent.visible_children_for(viewer)).to include(child)
      expect(parent.visible_children_for(priv)).to include(child)
    end

    it "hides a reply authored by someone in the viewer's hidden set (block)" do
      blocked = create(:user)
      child = create(:hujah, user: blocked, parent: parent)
      viewer.blocks_made.create!(blocked: blocked)
      expect(parent.visible_children_for(viewer)).not_to include(child)
    end
  end
end
