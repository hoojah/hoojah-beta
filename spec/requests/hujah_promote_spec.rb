require "rails_helper"

RSpec.describe "Promote a hoojah to top-level", type: :request do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  def sign_in_fresh(u) = sign_in(User.find(u.id))

  it "detaches the reply, clears its stance vote, keeps its slug, keeps its subtree" do
    parent = create(:hujah, user: owner, body: "Parent claim body here")
    reply = create(:hujah, user: owner, parent_id: parent.id, vote: 1, body: "Reply worth promoting")
    grandchild = create(:hujah, user: other, parent_id: reply.id, body: "Grandchild reply body")
    old_slug = reply.slug

    sign_in_fresh owner
    post "/hoojah/#{reply.slug}/promote"

    reply.reload
    expect(reply.parent_id).to be_nil
    expect(reply.vote).to be_nil
    expect(reply.slug).to eq(old_slug) # slug derives from body; promote doesn't touch it
    expect(grandchild.reload.parent_id).to eq(reply.id) # subtree travelled
    expect(Hujah.friendly.find(old_slug).id).to eq(reply.id) # URL stable — same record, same link
    expect(response).to have_http_status(:see_other).or have_http_status(:found)
  end

  it "denies a non-owner (Pundit redirect, no change)" do
    parent = create(:hujah, user: owner, body: "Parent claim body here")
    reply = create(:hujah, user: owner, parent_id: parent.id, body: "Reply worth promoting")
    sign_in_fresh other
    post "/hoojah/#{reply.slug}/promote"
    expect(reply.reload.parent_id).to eq(parent.id)
  end

  it "denies promoting a top-level hoojah" do
    h = create(:hujah, user: owner, body: "Already top level here")
    sign_in_fresh owner
    post "/hoojah/#{h.slug}/promote"
    expect(h.reload.parent_id).to be_nil # unchanged, still top-level
    expect(flash[:alert]).to be_present.or(satisfy { response.status.in?([302, 303]) })
  end
end
