require "rails_helper"

RSpec.describe "Rate limiting", type: :request do
  before {
    Rack::Attack.enabled = true
    Rack::Attack.reset!
  }
  after { Rack::Attack.enabled = false }

  it "throttles repeated failed logins from one IP" do
    11.times { post "/login", params: {user: {email: "x@x.com", password: "nope"}} }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles compose (POST /hoojah) per user beyond the limit" do
    user = create(:user)
    sign_in user

    21.times { post "/hoojah", params: {hujah: {body: "spammy take"}} }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles flag (POST /hoojah/:slug/flags) per user beyond the limit" do
    user = create(:user)
    hujah = create(:hujah)
    sign_in user

    16.times { post "/hoojah/#{hujah.slug}/flags", params: {flag: {subject: "spam"}} }
    expect(response).to have_http_status(:too_many_requests)
  end
end
