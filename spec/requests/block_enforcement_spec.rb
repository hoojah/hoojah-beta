require "rails_helper"

# After A blocks B, B's interactions with A are rejected AT THE POLICY LAYER — no
# content and no notification is ever created. Bidirectional: the block is symmetric
# so B is hidden from A too, but these specs drive B (the blocked user) reaching for A.
RSpec.describe "Block enforcement (policy-layer rejections)", type: :request do
  let(:a) { create(:user, username: "aaa") }
  let(:b) { create(:user, username: "bbb") }
  # turbo-stream-only Accept → the global Pundit handler's `format.any` returns a
  # flat 403 (a text/html Accept would redirect_back instead).
  let(:ts) { {"Accept" => "text/vnd.turbo-stream.html"} }

  before { a.blocks_made.create!(blocked: b) }

  it "rejects B's reply to A's hoojah — 403, no new_hoojah_response notification" do
    hoojah = create(:hujah, user: a)
    sign_in b
    expect {
      post "/hoojah", params: {hujah: {body: "sneaky reply", parent_id: hoojah.id, vote: 1}}, headers: ts
    }.not_to change { Notification.where(category: "new_hoojah_response").count }
    expect(response).to have_http_status(:forbidden)
  end

  it "rejects B following A — no new_follower notification" do
    sign_in b
    expect {
      post "/u/aaa/follow", headers: ts
    }.not_to change { Notification.where(category: "new_follower").count }
    expect(response).to have_http_status(:forbidden)
    expect(b.reload.following).not_to include(a)
  end

  it "rejects B challenging A to a debate — no debate_challenge notification" do
    hoojah = create(:hujah)
    argument = create(:hujah, parent: hoojah, user: a, vote: 3) # A authored the argument
    sign_in b
    expect {
      post "/hoojah/#{hoojah.slug}/debates", params: {argument_id: argument.id, challenger_stance: 1}, headers: ts
    }.not_to change { Notification.where(category: "debate_challenge").count }
    expect(response).to have_http_status(:forbidden)
    expect(Debate.count).to eq(0)
  end

  it "still records B's vote on A's hoojah — new_vote IS created (anonymous, deliberately not filtered)" do
    hoojah = create(:hujah, user: a)
    sign_in b
    expect {
      post "/hoojah/#{hoojah.slug}/votes", params: {vote: 1}, headers: ts
    }.to change { Notification.where(category: "new_vote").count }.by(1)
  end
end
