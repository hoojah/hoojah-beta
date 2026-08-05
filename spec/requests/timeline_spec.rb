require "rails_helper"

RSpec.describe "Following feed", type: :request do
  let(:me) { create(:user) }
  let(:followed) { create(:user) }
  let(:stranger) { create(:user) }
  before do
    me.active_follows.create!(followed: followed)
    @mine = create(:hujah, user: me)
    @theirs = create(:hujah, user: followed)
    @other = create(:hujah, user: stranger)
  end

  it "shows own + followed, not strangers, when signed in" do
    sign_in me
    get "/", params: {filter: "following"}
    expect(response.body).to include(@mine.slug).and include(@theirs.slug)
    expect(response.body).not_to include(@other.slug)
  end

  it "falls back to the global feed for an anonymous following request (no 500)" do
    get "/", params: {filter: "following"}
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(@other.slug) # global feed
  end
end
