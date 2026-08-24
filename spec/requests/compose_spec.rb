require "rails_helper"

RSpec.describe "Compose", type: :request do
  let(:user) { create(:user) }

  it "requires login to open the form" do
    get new_hujah_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "creates a top-level hoojah and redirects to it" do
    sign_in user
    expect { post "/hoojah", params: {hujah: {body: "My take on this"}} }
      .to change(Hujah, :count).by(1)
    expect(response).to have_http_status(:see_other)
  end

  it "creates a response with a stance + notifies the parent owner" do
    sign_in user
    parent = create(:hujah, user: create(:user))
    # 2026 vote-to-respond gate: the replier must vote on the parent before replying.
    parent.cast_vote(by: user, choice: 1)
    expect {
      post "/hoojah", params: {hujah: {body: "reply", parent_id: parent.id, vote: 1}}
    }.to change { Notification.where(category: "new_hoojah_response").count }.by(1)
    expect(Hujah.last.vote).to eq([1]).or eq(1) # matches the model's vote column shape
  end

  it "rejects a spoofed missing parent_id" do
    sign_in user
    post "/hoojah", params: {hujah: {body: "x", parent_id: 999_999}}
    expect(response).to have_http_status(:not_found).or have_http_status(:unprocessable_content)
  end

  it "persists visibility and allow_debates on create" do
    sign_in user
    post "/hoojah", params: {hujah: {body: "A brand new claim about transit", visibility: "private_only", allow_debates: "0"}}
    h = Hujah.order(:created_at).last
    expect(h.visibility).to eq "private_only"
    expect(h.allow_debates).to be false
  end

  it "rejects a reply before the replier has voted on the parent (2026 gate)" do
    sign_in user
    parent = create(:hujah, user: create(:user))
    expect { post "/hoojah", params: {hujah: {body: "no vote yet reply", parent_id: parent.id, vote: "1"}} }
      .not_to change(Hujah, :count)
    # Pundit#NotAuthorizedError → HTML redirect back with an alert.
    expect(response).to have_http_status(:forbidden).or have_http_status(:found)
  end

  # SECURITY: the respond composer renders the parent claim's body via _parent_card, so
  # #new must authorize(@parent, :show?) — otherwise a signed-in non-follower reads the
  # body of a followers_only / private_only claim just by guessing its slug.
  it "does not leak a followers_only parent's body to a non-follower on the respond page" do
    author = create(:user)
    parent = create(:hujah, user: author, visibility: :followers_only, body: "FOLLOWERS_ONLY_SECRET body")
    sign_in user # a non-follower
    get respond_hujah_path(parent.slug)
    expect(response).to have_http_status(:redirect)
    expect(response.body).not_to include("FOLLOWERS_ONLY_SECRET body")
  end

  it "does not leak a private_only parent's body to a stranger on the respond page" do
    author = create(:user)
    parent = create(:hujah, user: author, visibility: :private_only, body: "PRIVATE_ONLY_SECRET body")
    sign_in user # a stranger
    get respond_hujah_path(parent.slug)
    expect(response).to have_http_status(:redirect)
    expect(response.body).not_to include("PRIVATE_ONLY_SECRET body")
  end

  it "still lets an accepted follower open the respond page for a followers_only parent" do
    author = create(:user)
    parent = create(:hujah, user: author, visibility: :followers_only, body: "FOLLOWERS_ONLY_VISIBLE body")
    user.active_follows.create!(followed: author, status: :accepted)
    sign_in user
    get respond_hujah_path(parent.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("FOLLOWERS_ONLY_VISIBLE body")
  end
end
