require "rails_helper"

RSpec.describe "Content Security Policy", type: :request do
  it "permits blob: image previews and the garage direct-upload host" do
    get root_path
    expect(response).to have_http_status(:ok)
    csp = response.headers["Content-Security-Policy"]
    expect(csp[/img-src[^;]*/]).to include("blob:")
    expect(csp[/connect-src[^;]*/])
      .to include(ENV.fetch("GARAGE_ENDPOINT", "https://s3-grg.novas.my"))
  end
end
