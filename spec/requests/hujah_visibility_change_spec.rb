require "rails_helper"

RSpec.describe "Change hoojah visibility", type: :request do
  let(:owner) { create(:user, username: "owner") }
  let(:follower) { create(:user, username: "follower") }
  let(:stranger) { create(:user, username: "stranger") }
  def sign_in_fresh(u) = sign_in(User.find(u.id))
  def accept_follow(from:, to:) = from.active_follows.create!(followed: to, status: :accepted)

  describe "loosening never purges" do
    it "widens the audience and touches no votes/arguments" do
      h = create(:hujah, user: owner, visibility: :followers_only)
      h.cast_vote(by: stranger, choice: 1)
      sign_in_fresh owner
      expect {
        patch "/hoojah/#{h.slug}/visibility", params: {hujah: {visibility: "visible_public"}}
      }.not_to change(HujahArchive, :count)
      expect(h.reload.visibility).to eq("visible_public")
      expect(Vote.exists?(hujah_id: h.id, user_id: stranger.id)).to be(true)
    end
  end

  describe "tightening happy path" do
    it "purges after the confirm word is typed" do
      h = create(:hujah, user: owner, visibility: :visible_public)
      h.cast_vote(by: stranger, choice: 1)
      sign_in_fresh owner
      expect {
        patch "/hoojah/#{h.slug}/visibility",
          params: {hujah: {visibility: "private_only"}, confirm: HujahsController::VISIBILITY_CONFIRM_WORD}
      }.to change(HujahArchive, :count).by(1)
      expect(h.reload.visibility).to eq("private_only")
      expect(Vote.exists?(hujah_id: h.id, user_id: stranger.id)).to be(false)
    end
  end

  describe "fail closed" do
    it "does NOT purge when the confirm word is wrong" do
      h = create(:hujah, user: owner, visibility: :visible_public)
      h.cast_vote(by: stranger, choice: 1)
      sign_in_fresh owner
      expect {
        patch "/hoojah/#{h.slug}/visibility",
          params: {hujah: {visibility: "private_only"}, confirm: "nope"}
      }.not_to change(HujahArchive, :count)
      expect(h.reload.visibility).to eq("visible_public")
      expect(response).to redirect_to(visibility_hujah_path(h.slug, to: "private_only"))
    end

    it "blocks when an affected argument is entangled, even with the confirm word" do
      h = create(:hujah, user: owner, visibility: :visible_public)
      h.cast_vote(by: stranger, choice: 1)
      arg = create(:hujah, user: stranger, parent_id: h.id, body: "An entangled argument")
      arg.cast_vote(by: create(:user), choice: 2)
      sign_in_fresh owner
      expect {
        patch "/hoojah/#{h.slug}/visibility",
          params: {hujah: {visibility: "private_only"}, confirm: HujahsController::VISIBILITY_CONFIRM_WORD}
      }.not_to change(HujahArchive, :count)
      expect(h.reload.visibility).to eq("visible_public")
    end

    it "unblocks after the argument owner promotes the entangled argument" do
      h = create(:hujah, user: owner, visibility: :visible_public)
      h.cast_vote(by: stranger, choice: 1)
      arg = create(:hujah, user: stranger, parent_id: h.id, body: "An entangled argument")
      arg.cast_vote(by: create(:user), choice: 2)
      arg.promote!
      sign_in_fresh owner
      expect {
        patch "/hoojah/#{h.slug}/visibility",
          params: {hujah: {visibility: "private_only"}, confirm: HujahsController::VISIBILITY_CONFIRM_WORD}
      }.to change(HujahArchive, :count).by(1)
      expect(h.reload.visibility).to eq("private_only")
    end
  end

  describe "authorization + form" do
    it "renders the confirmation counts on the edit screen for a tighten target" do
      h = create(:hujah, user: owner, visibility: :visible_public)
      h.cast_vote(by: stranger, choice: 1)
      sign_in_fresh owner
      get "/hoojah/#{h.slug}/visibility", params: {to: "private_only"}
      expect(response.body).to include(HujahsController::VISIBILITY_CONFIRM_WORD)
    end

    it "denies a non-owner" do
      h = create(:hujah, user: owner, visibility: :visible_public)
      sign_in_fresh stranger
      get "/hoojah/#{h.slug}/visibility"
      expect(response).to have_http_status(:redirect)
    end

    it "renders the entangled blockers on the confirmation screen without erroring" do
      # blockers are partial-select records (no body/slug); the controller reloads them
      # as @blocker_args so the view can render body/slug — this proves no
      # ActiveModel::MissingAttributeError leaks through to the confirmation screen.
      h = create(:hujah, user: owner, visibility: :visible_public)
      h.cast_vote(by: stranger, choice: 1)
      arg = create(:hujah, user: stranger, parent_id: h.id, body: "A blocking entangled argument")
      arg.cast_vote(by: create(:user), choice: 2)
      sign_in_fresh owner

      get "/hoojah/#{h.slug}/visibility", params: {to: "private_only"}

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Blocked")
      expect(response.body).to include("A blocking entangled argument")
      # and the typed-confirm field is NOT offered while blocked
      expect(response.body).not_to include("Tighten visibility permanently")
    end
  end
end
