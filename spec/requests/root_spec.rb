require "rails_helper"
RSpec.describe "Root", type: :request do
  it "renders the HTML shell (not a JS pack)" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include('id="hujah-feed"')
  end
end
