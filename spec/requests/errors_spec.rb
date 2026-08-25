require "rails_helper"

RSpec.describe "Branded error pages", type: :request do
  # ActionDispatch::Static sits ahead of routing and serves public/404.html for a
  # GET /404 (in test with static serving on, and in production). The real branded
  # page is reached via config.exceptions_app, which redispatches the FAILED request
  # — original verb intact — straight to this route, bypassing Static. These specs
  # POST to exercise ErrorsController#show the same way (Static ignores non-GET/HEAD;
  # the routes are `via: :all`), which is more representative of the exceptions_app
  # path than a GET that Static would shadow.

  it "renders a branded 404 with the correct status" do
    post "/404"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("That page doesn't exist")
    expect(response.body).to include(root_path)
  end

  it "renders a branded 422 with the correct status" do
    post "/422"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("That request couldn't be processed")
  end

  it "renders a branded 500 with the correct status" do
    post "/500"
    expect(response).to have_http_status(:internal_server_error)
    expect(response.body).to include("Something went wrong")
  end

  it "skips CSRF on the error route so a tokenless POST still renders (H1)" do
    # The test env disables forgery protection, so a plain POST can't prove the skip
    # does anything. Flip it ON: without ErrorsController's
    # `skip_before_action :verify_authenticity_token`, this tokenless POST would raise
    # InvalidAuthenticityToken inside ShowExceptions and collapse to Rails' bare
    # failsafe. It must still render the branded 422.
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post "/422"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("That request couldn't be processed")
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it "returns JSON for a JSON client instead of the HTML body" do
    post "/404", headers: {"Accept" => "application/json"}
    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/json")
  end

  it "no longer swallows a missing tag slug into a blank body" do
    # A missing slug is not a static file, so GET reaches the controller. The rescue
    # that turned this into a blank head :not_found is gone; RecordNotFound now
    # propagates (to the branded 404 via exceptions_app in prod). Test env runs
    # show_exceptions=:none, so here it surfaces as a raise.
    expect { get "/t/definitely-not-a-real-tag" }
      .to raise_error(ActiveRecord::RecordNotFound)
  end
end
