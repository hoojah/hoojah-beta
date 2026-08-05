require "rails_helper"

# Secure-behavior characterization of the JSON notifications API (Slice 2, Pundit).
# These lock the IDOR/leak fixes: index is scoped to the signed-in user, and
# update/destroy on someone else's notification are forbidden, not silently allowed.
RSpec.describe "Api::V1::Notifications", type: :request do
  let(:me) { create(:user) }
  let(:other) { create(:user) }

  it "index returns only the current user notifications" do
    mine = create(:notification, user: me)
    create(:notification, user: other)
    sign_in me
    get "/api/v1/#{me.username}/notifications", as: :json
    body = JSON.parse(response.body)
    ids = body["data"].map { |n| n["id"].to_i }
    expect(ids).to eq([mine.id])
  end

  it "forbids updating/destroying another user notification" do
    theirs = create(:notification, user: other)
    sign_in me
    put "/api/v1/#{me.username}/notifications/#{theirs.id}", params: {notification: {read: true}}, as: :json
    expect(response).to have_http_status(:forbidden)
    delete "/api/v1/#{me.username}/notifications/#{theirs.id}", as: :json
    expect(response).to have_http_status(:forbidden)
    expect(Notification.exists?(theirs.id)).to be(true)
  end

  it "requires auth" do
    get "/api/v1/#{me.username}/notifications", as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  # Slice 5 Part A: a new_vote notification must never serialize a subject_user
  # (that would hand the owner the first voter's identity). Categories that name a
  # legitimately public actor (e.g. new_hoojah_response) still carry subject_user.
  it "omits subject_user for new_vote but keeps it for new_hoojah_response" do
    voter = create(:user, username: "the_voter")
    replier = create(:user, username: "the_replier")
    hujah = create(:hujah, user: me)
    new_vote = create(:notification, user: me, hujah: hujah,
      category: :new_vote, subject_user: nil)
    response_notification = create(:notification, user: me, hujah: hujah,
      category: :new_hoojah_response, subject_user: replier)
    _voter = voter # referenced only to document the leak we are closing

    sign_in me
    get "/api/v1/#{me.username}/notifications", as: :json
    body = JSON.parse(response.body)
    by_id = body["data"].index_by { |n| n["id"].to_i }

    # The serializer's `if subject_user_id` guard yields nil, so no username is
    # ever emitted for a new_vote — the identity leak is closed.
    expect(by_id[new_vote.id]["attributes"]["subject_user"]).to be_nil
    expect(by_id[response_notification.id]["attributes"]["subject_user"])
      .to eq("username" => "the_replier")
  end
end
