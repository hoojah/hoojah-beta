require "rails_helper"

# Phase 1.7-fix: the live-debate strip (hujahs/_live_debate_strip) and the
# swords/"Jump in" footer (hujahs/_hujah_card) render `@challenger vs @opponent
# · Round N` for a hujah's ACTIVE debate straight off `hujah.active_debate`,
# which HujahsController#preload_active_debates populates with NO visibility
# check. That bypasses DebatePolicy (an active debate is participant-only
# there) and leaks:
#   1. a private-account participant's handle + live activity to every feed
#      viewer, including anonymous
#   2. a blocked participant's handle to a viewer who blocked them
#
# Both surfaces are driven by the same preload, so one Ruby filter there closes
# both leaks. This spec asserts on the rendered participant handles ("vs" text)
# and the "Jump in" footer pill, not just absence of a crash.
RSpec.describe "Feed live-debate teaser visibility", type: :request do
  # In production current_user is loaded FRESH from the session on every
  # request; Devise's request-spec `sign_in` instead reuses the passed object,
  # and `User#hidden_user_ids` is memoized per-instance. Signing in a
  # freshly-loaded user (see block_visibility_spec, private_visibility_spec)
  # faithfully models the real per-request load.
  def sign_in_fresh(user) = sign_in(User.find(user.id))

  def vs_text(challenger, opponent) = "@#{challenger.username} vs @#{opponent.username}"

  describe "a public claim with an active debate whose CHALLENGER is a private account" do
    let!(:author) { create(:user, username: "author") }
    let!(:claim) { create(:hujah, user: author, visibility: :visible_public, body: "A public claim to debate on") }
    let!(:challenger) { create(:user, username: "privchallenger", private: true) }
    let!(:opponent) { create(:user, username: "openopp") }
    let!(:debate) { create(:debate, hujah: claim, challenger: challenger, opponent: opponent, status: :active) }

    it "does not leak the strip/footer to an anonymous viewer" do
      get "/"
      expect(response.body).not_to include(vs_text(challenger, opponent))
      expect(response.body).not_to include("Jump in")
    end

    it "does not leak the strip/footer to a signed-in non-follower" do
      stranger = create(:user, username: "stranger")
      sign_in_fresh stranger
      get "/"
      expect(response.body).not_to include(vs_text(challenger, opponent))
      expect(response.body).not_to include("Jump in")
    end

    it "shows the strip/footer to a debate participant (the private challenger themselves)" do
      sign_in_fresh challenger
      get "/"
      expect(response.body).to include(vs_text(challenger, opponent))
      expect(response.body).to include("Jump in")
    end

    it "shows the strip/footer to an accepted follower of the private challenger" do
      follower = create(:user, username: "follower")
      follower.active_follows.create!(followed: challenger, status: :accepted)
      sign_in_fresh follower
      get "/"
      expect(response.body).to include(vs_text(challenger, opponent))
      expect(response.body).to include("Jump in")
    end
  end

  describe "a public claim with an active debate between two PUBLIC users" do
    let!(:author) { create(:user, username: "author2") }
    let!(:claim) { create(:hujah, user: author, visibility: :visible_public, body: "Another public claim to debate on") }
    let!(:challenger) { create(:user, username: "pubchallenger") }
    let!(:opponent) { create(:user, username: "pubopp") }
    let!(:debate) { create(:debate, hujah: claim, challenger: challenger, opponent: opponent, status: :active) }

    it "shows the strip/footer to everyone, including anonymous — the intended 2026 feature" do
      get "/"
      expect(response.body).to include(vs_text(challenger, opponent))
      expect(response.body).to include("Jump in")
    end
  end

  describe "a viewer who has blocked one participant" do
    let!(:author) { create(:user, username: "author3") }
    let!(:claim) { create(:hujah, user: author, visibility: :visible_public, body: "Yet another public claim to debate on") }
    let!(:challenger) { create(:user, username: "blockedchal") }
    let!(:opponent) { create(:user, username: "cleanopp") }
    let!(:debate) { create(:debate, hujah: claim, challenger: challenger, opponent: opponent, status: :active) }

    it "does not show the strip/footer to a viewer who blocked the challenger" do
      blocker = create(:user, username: "blocker")
      blocker.blocks_made.create!(blocked: challenger)
      sign_in_fresh blocker
      get "/"
      expect(response.body).not_to include(vs_text(challenger, opponent))
      expect(response.body).not_to include("Jump in")
    end

    it "still shows the strip/footer to a different signed-in viewer with no block" do
      other_viewer = create(:user, username: "noblockviewer")
      sign_in_fresh other_viewer
      get "/"
      expect(response.body).to include(vs_text(challenger, opponent))
      expect(response.body).to include("Jump in")
    end
  end
end
