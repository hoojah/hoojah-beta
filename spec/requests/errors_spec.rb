require "rails_helper"

RSpec.describe "Branded error pages", type: :request do
  it "renders a branded 404 with the correct status" do
    get "/404"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("That page doesn't exist")
    expect(response.body).to include(root_path)
  end

  it "renders a branded 422 with the correct status" do
    get "/422"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("That request couldn't be processed")
  end

  it "renders a branded 500 with the correct status" do
    get "/500"
    expect(response).to have_http_status(:internal_server_error)
    expect(response.body).to include("Something went wrong")
  end

  it "renders the branded 422 even for a POST (CSRF-failure verb survives redispatch)" do
    post "/422"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("That request couldn't be processed")
  end

  it "skips CSRF on the error route so a tokenless POST still renders (H1)" do
    # The test env disables forgery protection, so the plain POST above can't prove
    # the skip does anything. Flip it ON: without ErrorsController's
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
    get "/404", headers: {"Accept" => "application/json"}
    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/json")
  end

  it "no longer swallows a missing tag slug into a blank body" do
    # config.action_dispatch.show_exceptions = :none in this project's test env
    # (config/environments/test.rb), so a propagating RecordNotFound raises here
    # rather than being rendered as a response — it never reaches exceptions_app.
    expect { get "/t/definitely-not-a-real-tag" }
      .to raise_error(ActiveRecord::RecordNotFound)
  end
end
