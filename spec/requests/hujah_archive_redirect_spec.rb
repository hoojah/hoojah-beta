require "rails_helper"

RSpec.describe "Purged participant redirect to archive", type: :request do
  let(:owner) { create(:user, username: "owner") }
  let(:stranger) { create(:user, username: "stranger") }
  def sign_in_fresh(u) = sign_in(User.find(u.id))

  def purge_stranger!(hujah)
    hujah.cast_vote(by: stranger, choice: 1)
    VisibilityChange.new(hujah, to: "private_only").apply!
  end

  it "redirects a purged user from the live post to their frozen archive" do
    h = create(:hujah, user: owner, visibility: :visible_public, body: "Contested claim here")
    purge_stranger!(h)
    sign_in_fresh stranger
    get "/hoojah/#{h.slug}"
    expect(response).to redirect_to("/hoojah/#{h.slug}/archived")
  end

  it "renders the FULL frozen post (incl. the purged user's own vote/args) on the archive" do
    h = create(:hujah, user: owner, visibility: :visible_public, body: "Contested claim here")
    create(:hujah, user: stranger, parent_id: h.id, body: "Strangers own argument text")
    purge_stranger!(h)
    sign_in_fresh stranger
    get "/hoojah/#{h.slug}/archived"
    expect(response.body).to include("Contested claim here")
    expect(response.body).to include("Strangers own argument text")
  end

  it "does NOT redirect a still-visible user (owner sees the live post)" do
    h = create(:hujah, user: owner, visibility: :visible_public, body: "Contested claim here")
    purge_stranger!(h)
    sign_in_fresh owner
    get "/hoojah/#{h.slug}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Contested claim here")
  end

  it "a non-participant stranger cannot reach the archive" do
    h = create(:hujah, user: owner, visibility: :visible_public, body: "Contested claim here")
    purge_stranger!(h)
    outsider = create(:user, username: "outsider")
    sign_in_fresh outsider
    get "/hoojah/#{h.slug}/archived"
    expect(response).to have_http_status(:redirect)
  end

  # Secret ballot on the frozen snapshot: the archive is read by a purged VOTER, so the
  # per-stance breakdown must obey the same k-anonymity gate as live surfaces — otherwise
  # a viewer with only one co-voter deduces that person's stance from the archived counts.
  describe "k-anonymity on the archived breakdown" do
    it "hides the per-stance breakdown below the k threshold (shows only the total)" do
      # 2 total voters (< VOTE_BREAKDOWN_MIN = 3): the split must not be shown.
      h = create(:hujah, user: owner, visibility: :visible_public, body: "Low-vote claim body here")
      viewer = create(:user, username: "viewer")
      h.cast_vote(by: viewer, choice: 1)
      h.cast_vote(by: create(:user, username: "cov"), choice: 3)
      VisibilityChange.new(h, to: "private_only").apply!

      sign_in_fresh viewer
      get "/hoojah/#{h.slug}/archived"
      expect(response.body).to include("2 votes")
      expect(response.body).not_to include("agree:")
      expect(response.body).not_to include("disagree:")
    end

    it "shows the per-stance breakdown at/above the k threshold" do
      h = create(:hujah, user: owner, visibility: :visible_public, body: "High-vote claim body here")
      viewer = create(:user, username: "viewer")
      h.cast_vote(by: viewer, choice: 1)
      h.cast_vote(by: create(:user, username: "cov1"), choice: 2)
      h.cast_vote(by: create(:user, username: "cov2"), choice: 3)
      VisibilityChange.new(h, to: "private_only").apply!

      sign_in_fresh viewer
      get "/hoojah/#{h.slug}/archived"
      expect(response.body).to include("agree:")
      expect(response.body).to include("disagree:")
    end
  end
end
