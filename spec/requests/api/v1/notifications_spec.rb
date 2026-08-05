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
end
