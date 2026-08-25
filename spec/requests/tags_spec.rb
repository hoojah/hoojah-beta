require "rails_helper"

RSpec.describe "Tag feed", type: :request do
  it "lists public claims carrying the tag" do
    tagged = create(:hujah, body: "Cheaper fares on the #MRT line for everyone please")
    create(:hujah, body: "Unrelated claim with enough length here")
    get "/t/mrt"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(tagged.slug)
  end

  it "404s on an unknown tag" do
    # Task 8: the controller no longer rescues RecordNotFound into a blank
    # head :not_found — it propagates to the branded 404 (config.exceptions_app
    # = routes in production). This project's test env runs
    # action_dispatch.show_exceptions = :none, so here it surfaces as a raise
    # rather than a rendered response (see spec/requests/errors_spec.rb).
    expect { get "/t/nosuchtag" }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "is case-insensitive on the tag name" do
    tagged = create(:hujah, body: "Support the #KlangValley transit plan today")
    get "/t/klangvalley"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(tagged.slug)
  end

  describe "per-post visibility" do
    it "excludes a followers_only claim carrying the tag" do
      hidden = create(:hujah, visibility: :followers_only,
        body: "Private plan for the #MRT extension route here")
      shown = create(:hujah, visibility: :visible_public,
        body: "Open plan for the #MRT extension route here")
      get "/t/mrt"
      expect(response.body).to include(shown.slug)
      expect(response.body).not_to include(hidden.slug)
    end

    it "excludes a private author's claim carrying the tag" do
      private_author = create(:user, private: true)
      hidden = create(:hujah, user: private_author,
        body: "Locked account posting about #MRT plans here")
      shown = create(:hujah, body: "Public account posting about #MRT plans here")
      get "/t/mrt"
      expect(response.body).to include(shown.slug)
      expect(response.body).not_to include(hidden.slug)
    end
  end

  describe "empty state" do
    it "shows an empty state when a tag has no visible hoojahs" do
      tag = create(:hashtag)
      get tag_path(tag.name)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No hoojahs tagged")
    end

    it "shows a compose CTA to a signed-in visitor on an empty tag" do
      tag = create(:hashtag)
      sign_in create(:user)
      get tag_path(tag.name)
      expect(response.body).to include(new_hujah_path)
    end

    it "shows no compose CTA to an anonymous visitor on an empty tag" do
      tag = create(:hashtag)
      get tag_path(tag.name)
      expect(response.body).not_to include("Post a hoojah")
    end
  end
end
