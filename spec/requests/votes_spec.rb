require "rails_helper"

RSpec.describe "Votes", type: :request do
  it "records a conviction vote when conviction=1" do
    user = create(:user)
    sign_in user
    h = create(:hujah)
    post hujah_votes_path(h.slug), params: {vote: "1", conviction: "1"}
    expect(h.reload.conviction_count).to eq 1
    expect(h.votes.find_by(user: user).conviction).to be true
  end

  it "records a normal vote when conviction is absent" do
    user = create(:user)
    sign_in user
    h = create(:hujah)
    post hujah_votes_path(h.slug), params: {vote: "1"}
    expect(h.reload.conviction_count).to eq 0
    expect(h.votes.find_by(user: user).conviction).to be false
  end
end
