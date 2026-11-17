require "rails_helper"

RSpec.describe "Favourite a response", type: :request do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  let(:parent) { create(:hujah, user: owner, body: "Parent claim body here") }
  def sign_in_fresh(u) = sign_in(User.find(u.id))
  def reply(vote:, user: other) = create(:hujah, user: user, parent_id: parent.id, vote: vote)

  it "lets the parent author star and unstar a reply" do
    r = reply(vote: 1)
    sign_in_fresh owner

    post "/hoojah/#{r.slug}/favourite"
    expect(response).to redirect_to("/hoojah/#{parent.slug}")
    expect(r.reload).to be_favourited

    delete "/hoojah/#{r.slug}/favourite"
    expect(r.reload).not_to be_favourited
  end

  it "does not bump the reply's updated_at" do
    r = reply(vote: 1)
    r.update_columns(updated_at: 2.days.ago)
    sign_in_fresh owner
    expect { post "/hoojah/#{r.slug}/favourite" }.not_to(change { r.reload.updated_at })
  end

  it "caps favourites at 5 per stance, independently for each stance" do
    agrees = Array.new(6) { reply(vote: 1) }
    disagree = reply(vote: 3)
    sign_in_fresh owner

    agrees.first(5).each { |r| post "/hoojah/#{r.slug}/favourite" }
    post "/hoojah/#{agrees.last.slug}/favourite"
    expect(agrees.last.reload).not_to be_favourited
    expect(flash[:alert]).to include("up to 5 agree responses")

    post "/hoojah/#{disagree.slug}/favourite"
    expect(disagree.reload).to be_favourited
    expect(parent.children.favourited.where(vote: 1).count).to eq(5)
  end

  it "frees a slot when a favourite is moderator-removed" do
    agrees = Array.new(6) { reply(vote: 1) }
    agrees.first(5).each { |r| r.update_columns(favourited_at: Time.current) }
    agrees.first.update_columns(moderation_status: Hujah.moderation_statuses[:removed])

    sign_in_fresh owner
    post "/hoojah/#{agrees.last.slug}/favourite"
    expect(agrees.last.reload).to be_favourited
  end

  it "refuses anyone but the parent author" do
    r = reply(vote: 1)
    sign_in_fresh other
    post "/hoojah/#{r.slug}/favourite"
    expect(r.reload).not_to be_favourited
  end

  it "refuses a top-level hoojah" do
    sign_in_fresh owner
    post "/hoojah/#{parent.slug}/favourite"
    expect(parent.reload).not_to be_favourited
  end

  it "requires sign-in" do
    r = reply(vote: 1)
    post "/hoojah/#{r.slug}/favourite"
    expect(response).to redirect_to(new_user_session_path)
    expect(r.reload).not_to be_favourited
  end

  it "lists favourites first and shows the toggle only to the parent author" do
    plain = reply(vote: 2)
    starred = reply(vote: 2)
    plain.update_columns(updated_at: 1.minute.from_now)
    starred.update_columns(favourited_at: Time.current)

    sign_in_fresh owner
    get "/hoojah/#{parent.slug}"
    expect(response.body.index(starred.slug)).to be < response.body.index(plain.slug)
    expect(response.body).to include("Unfavourite response")

    sign_in_fresh other
    get "/hoojah/#{parent.slug}"
    expect(response.body).not_to include("Favourite response")
    expect(response.body).to include("Author&#39;s pick").or include("Author's pick")
  end

  it "clears the favourite when the reply is promoted" do
    r = reply(vote: 1, user: owner)
    r.update_columns(favourited_at: Time.current)
    r.promote!
    expect(r.reload).not_to be_favourited
  end
end
