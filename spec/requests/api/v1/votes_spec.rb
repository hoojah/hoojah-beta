require "rails_helper"

RSpec.describe "Api::V1::Votes", type: :request do
  let(:owner) { create(:user) }
  let(:voter) { create(:user) }
  let(:attacker) { create(:user) }
  let(:hujah) { create(:hujah, user: owner) }

  it "requires authentication" do
    post "/api/v1/votes/create", params: {vote: 1, hujah_id: hujah.id}, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "records the vote under the SESSION user, ignoring a supplied user_id" do
    sign_in voter
    post "/api/v1/votes/create",
      params: {vote: 1, hujah_id: hujah.id, user_id: attacker.id}, as: :json
    expect(response).to have_http_status(:ok).or have_http_status(:created)
    expect(Vote.where(user: voter, hujah: hujah)).to exist
    expect(Vote.where(user: attacker)).to be_empty
  end
end
