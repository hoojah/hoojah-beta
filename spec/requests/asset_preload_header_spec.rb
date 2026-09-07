require "rails_helper"

# `config.action_view.preload_links_header = false` (config/application.rb). Rails
# otherwise emits a `Link: <...tailwind.css>; rel=preload; as=style` header for the
# render-blocking stylesheet, which Turbo Drive re-preloads on every visit without
# ever using — the browser console's "preloaded ... but not used" warning.
RSpec.describe "Asset preload headers", type: :request do
  it "does not emit a rel=preload Link header for the stylesheet" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.headers["Link"].to_s).not_to include("rel=preload")
  end
end
