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

  it "lets Drift boot its widget: strict-dynamic scripts and a driftt.com frame" do
    get root_path
    csp = response.headers["Content-Security-Policy"]
    # strict-dynamic so Drift's runtime-injected <script>s inherit nonce trust.
    expect(csp[/script-src[^;]*/]).to include("'strict-dynamic'")
    # Drift frames js.driftt.com (double-t), not only *.drift.com.
    expect(csp[/frame-src[^;]*/]).to include("https://*.driftt.com")
  end
end
