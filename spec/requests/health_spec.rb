require "rails_helper"

# The container health endpoint added in Slice 10b. Coolify polls it to decide whether a
# deploy went live, so a regression here does not surface as a failing page — it surfaces
# as a deploy that hangs "unhealthy" or, worse, one that rolls back a good release.
RSpec.describe "Health check", type: :request do
  it "answers /up with 200 and the green health page, unauthenticated" do
    get "/up"

    expect(response).to have_http_status(:ok)
    # Rails::HealthController renders a fixed green page. Asserting on it (rather than
    # only the status) is what distinguishes "the app booted" from "some other route
    # happened to match /up and returned 200".
    expect(response.body).to include("background-color: green")
  end

  # `rails/health#show` descends from ActionController::Base, NOT from this app's
  # ApplicationController, so it never runs the `after_action :verify_authorized` that
  # every other non-Devise action here must satisfy. That is worth pinning: if someone
  # ever re-points /up at an app controller, this catches the resulting Pundit raise.
  it "does not go through the Pundit authorization gate" do
    expect(Rails.application.routes.recognize_path("/up")).to eq(controller: "rails/health", action: "show")
    expect(Rails::HealthController.ancestors).not_to include(Pundit::Authorization)
  end

  # Host authorization is OFF in this environment (Rails only seeds `config.hosts` in
  # development, and production seeds it from APP_HOST), so a request spec cannot
  # exercise the production behaviour directly. What it CAN do is pin the production
  # config, which is the thing that actually regresses.
  #
  # Why it matters: Coolify probes the container over the internal Docker network — by
  # container IP or internal hostname, never by APP_HOST — so with `config.hosts`
  # populated and no exclusion, the probe is answered 403 and the deploy never goes
  # healthy. Verified manually in Slice 10b against a real production-mode Puma:
  # with the exclusion `/up` + `Host: 10.42.0.7` → 200, without it → 403, while `/`
  # with the same wrong Host stays 403 either way.
  it "keeps /up excluded from host authorization in production" do
    production_config = Rails.root.join("config/environments/production.rb").read

    expect(production_config).to match(/config\.host_authorization\s*=.*exclude/m)
    expect(production_config).to include('request.path == "/up"')
  end
end
