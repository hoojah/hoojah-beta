require "rails_helper"

RSpec.describe "Short links", type: :request do
  it "301-redirects an opaque code to its stored internal path (works signed-out)" do
    hujah = create(:hujah)
    link = ShortLink.for(hujah)

    get "/s/#{link.code}"

    expect(response).to have_http_status(:moved_permanently)
    expect(response.headers["Location"]).to end_with("/hoojah/#{hujah.slug}")
  end

  it "raises RecordNotFound (branded 404) for an unknown code" do
    # Task-style: the controller does not rescue — it propagates to the branded
    # 404 (config.exceptions_app = routes in production). This project's test env
    # runs action_dispatch.show_exceptions = :none, so it surfaces as a raise.
    expect { get "/s/nosuch1" }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "follows the short link through to a public hoojah (full loop → 200)" do
    hujah = create(:hujah, visibility: :visible_public)
    link = ShortLink.for(hujah)

    get "/s/#{link.code}"
    follow_redirect!

    expect(response).to have_http_status(:ok)
  end
end
