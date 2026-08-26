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

  # A PATCH/PUT with no `notification` key must be a client error (400), not a
  # NoMethodError-on-nil 500. `notification_params` uses `require` (same pattern as
  # FlagsController) and the controller rescues ParameterMissing → :bad_request.
  describe "update param robustness" do
    it "returns 400 (not 500) when the notification param key is missing" do
      mine = create(:notification, user: me)
      sign_in me
      put "/api/v1/#{me.username}/notifications/#{mine.id}", params: {}, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "marks the notification read on the happy path" do
      mine = create(:notification, user: me, read: false)
      sign_in me
      put "/api/v1/#{me.username}/notifications/#{mine.id}", params: {notification: {read: true}}, as: :json
      expect(response).to have_http_status(:ok)
      expect(mine.reload.read).to be(true)
    end
  end

  describe "referenced hoojah visibility + robustness" do
    # Slice 11 Task 9: the serializer used `Hujah.find`, so a notification whose
    # referenced hoojah was later deleted raised RecordNotFound → 500 on index.
    # `belongs_to :hujah, optional: true` returns nil for a dangling id.
    it "does not 500 the index when a referenced hoojah was deleted" do
      recipient = create(:user)
      hujah = create(:hujah, user: create(:user))
      notif = create(:notification, user: recipient, hujah: hujah, category: :new_hoojah_response)
      hujah.destroy
      notif.reload

      sign_in recipient
      get "/api/v1/#{recipient.username}/notifications", as: :json

      expect(response).to have_http_status(:ok)
    end

    # Slice 7b Gate 9 guard: a private author's hoojah body must not leak through the API.
    it "omits the hoojah block when its author is private and unseen by the recipient" do
      recipient = create(:user)
      priv = create(:user, private: true)
      hujah = create(:hujah, user: priv, visibility: :visible_public)
      create(:notification, user: recipient, hujah: hujah, category: :new_hoojah_response)

      sign_in recipient
      get "/api/v1/#{recipient.username}/notifications", as: :json

      hujah_attrs = JSON.parse(response.body)["data"].map { |n| n.dig("attributes", "hujah") }.compact
      expect(hujah_attrs).to be_empty
    end
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
