require "rails_helper"

RSpec.describe "Hujah show", type: :request do
  it "renders the hujah, its vote bars, and threaded children" do
    user = create(:user)
    parent = create(:hujah, user: user)
    create(:hujah, user: user, parent: parent, body: "a child response")
    get "/hoojah/#{parent.slug}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dom_id(parent, :vote_bars))
    expect(response.body).to include("a child response")
    expect(response.body).to include('data-controller="response-filter"')
  end
end
