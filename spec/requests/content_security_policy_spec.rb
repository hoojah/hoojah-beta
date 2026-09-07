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

  it "keeps script-src to self + nonce, with no strict-dynamic or third-party hosts" do
    get root_path
    csp = response.headers["Content-Security-Policy"]
    script = csp[/script-src[^;]*/]
    expect(script).to include("'self'")
    expect(script).to match(/'nonce-[^']+'/)
    expect(script).not_to include("strict-dynamic")
  end

  it "carries no Drift hosts anywhere now the widget is removed" do
    get root_path
    csp = response.headers["Content-Security-Policy"]
    expect(csp).not_to include("drift")
  end
end
