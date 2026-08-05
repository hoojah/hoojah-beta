require "rails_helper"

# Content filters after A blocks B (bidirectional, signed-in only): global feed,
# following feed, a hoojah's reply thread (@children), and trending exclude the
# blocked pair's content in BOTH directions; a stranger and an anonymous visitor
# see everything (anonymous is deliberately unfiltered). A mention is filtered at
# the notify_mentions query.
RSpec.describe "Block visibility (content filters)", type: :request do
  let(:a) { create(:user, username: "aaa") }
  let(:b) { create(:user, username: "bbb") }
  let(:stranger) { create(:user, username: "ccc") }

  # In production current_user is loaded FRESH from the session on every request, so
  # `hidden_user_ids` (memoized per-instance) is always recomputed. Devise's request-spec
  # sign_in instead reuses the passed object — and the hujah factory's notify_mentions
  # callback memoizes the author's (then-empty) hidden set before the block exists.
  # Signing in a freshly-loaded user faithfully models the real per-request load.
  def sign_in_fresh(user) = sign_in(User.find(user.id))

  describe "global feed (/)" do
    let!(:a_hoojah) { create(:hujah, user: a, body: "AAA global take") }
    let!(:b_hoojah) { create(:hujah, user: b, body: "BBB global take") }
    before { a.blocks_made.create!(blocked: b) }

    it "hides B from A and A from B, but a stranger and anonymous see both" do
      sign_in_fresh a
      get "/"
      expect(response.body).to include("AAA global take")
      expect(response.body).not_to include("BBB global take")

      sign_in_fresh b
      get "/"
      expect(response.body).to include("BBB global take")
      expect(response.body).not_to include("AAA global take")

      sign_in_fresh stranger
      get "/"
      expect(response.body).to include("AAA global take").and include("BBB global take")

      sign_out :user
      get "/"
      expect(response.body).to include("AAA global take").and include("BBB global take")
    end
  end

  describe "following feed (/?filter=following) — the insurance clause" do
    it "excludes a hidden author even if a stale follow survives" do
      # Block via the model directly so the follow is NOT auto-removed — exercises
      # timeline_for's hidden_user_ids exclusion, not the follow-removal path.
      a.active_follows.create!(followed: b, status: :accepted)
      create(:hujah, user: b, body: "BBB followed take")
      create(:hujah, user: a, body: "AAA own take")
      a.blocks_made.create!(blocked: b)

      sign_in_fresh a
      get "/?filter=following"
      expect(response.body).to include("AAA own take")
      expect(response.body).not_to include("BBB followed take")
    end
  end

  describe "reply thread (@children on show)" do
    let(:parent) { create(:hujah, user: stranger, body: "the parent thread") }
    let!(:a_reply) { create(:hujah, parent: parent, user: a, body: "AAA reply text", vote: 1) }
    let!(:b_reply) { create(:hujah, parent: parent, user: b, body: "BBB reply text", vote: 3) }
    before { a.blocks_made.create!(blocked: b) }

    it "hides each blocked author's reply from the other, but not from a stranger or anonymous" do
      sign_in_fresh a
      get "/hoojah/#{parent.slug}"
      expect(response.body).to include("AAA reply text")
      expect(response.body).not_to include("BBB reply text")

      sign_in_fresh b
      get "/hoojah/#{parent.slug}"
      expect(response.body).to include("BBB reply text")
      expect(response.body).not_to include("AAA reply text")

      sign_in_fresh stranger
      get "/hoojah/#{parent.slug}"
      expect(response.body).to include("AAA reply text").and include("BBB reply text")

      sign_out :user
      get "/hoojah/#{parent.slug}"
      expect(response.body).to include("AAA reply text").and include("BBB reply text")
    end
  end

  describe "trending (/trending)" do
    before { Rails.cache.clear }

    it "excludes a blocked user's hoojah for the viewer but stays unfiltered for anonymous" do
      create(:hujah, user: b, body: "BBB trending take", agree_count: 5)
      a.blocks_made.create!(blocked: b)

      sign_in_fresh a
      get "/trending"
      expect(response.body).not_to include("BBB trending take")

      sign_out :user
      get "/trending"
      expect(response.body).to include("BBB trending take")
    end
  end

  describe "mentions" do
    it "creates no mention notification when the mentioner is blocked by the mentioned" do
      a.blocks_made.create!(blocked: b)
      sign_in_fresh b
      expect {
        post "/hoojah", params: {hujah: {body: "hey @aaa look at this"}}
      }.not_to change { Notification.where(category: "mention").count }
    end
  end
end
