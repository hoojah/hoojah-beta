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
end
