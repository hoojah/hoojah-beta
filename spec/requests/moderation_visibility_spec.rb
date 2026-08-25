require "rails_helper"

# Slice 3 (the enforcement sweep): a `moderation_removed` hoojah must vanish from
# every LIST/COUNT surface that does NOT already gate per-record via visible_to?.
# One fixture drives all of them: a public author with an active + a removed
# top-level claim (both tagged #swept), and an active + a removed reply under an
# active parent. Distinctive body tokens (ZALPHA/ZBETA/ZGAMMA/ZDELTA) make the
# include/not-include assertions unambiguous.
RSpec.describe "Moderation visibility sweep", type: :request do
  let(:author) { create(:user) }
  let(:member) { create(:user) }
  let(:moderator) { create(:user, :moderator) }

  let!(:active_top) { create(:hujah, user: author, body: "ZALPHA claim about swept content #swept") }
  let!(:removed_top) do
    create(:hujah, user: author, body: "ZBETA claim about swept content #swept")
      .tap { |h| h.update!(moderation_status: :removed) }
  end
  let!(:parent) { create(:hujah, body: "ZPARENT anchor claim for replies") }
  let!(:active_reply) { create(:hujah, parent: parent, user: author, body: "ZGAMMA reply") }
  let!(:removed_reply) do
    create(:hujah, parent: parent, user: author, body: "ZDELTA reply")
      .tap { |h| h.update!(moderation_status: :removed) }
  end

  describe "global feed GET /" do
    it "hides the removed claim from an anonymous viewer" do
      get "/"
      expect(response.body).to include("ZALPHA")
      expect(response.body).not_to include("ZBETA")
    end

    it "hides the removed claim from a signed-in member" do
      sign_in member
      get "/"
      expect(response.body).to include("ZALPHA")
      expect(response.body).not_to include("ZBETA")
    end
  end

  describe "following feed GET /?filter=following" do
    it "hides the removed claim from a follower" do
      member.active_follows.create!(followed: author, status: :accepted)
      sign_in member
      get "/", params: {filter: "following"}
      expect(response.body).to include("ZALPHA")
      expect(response.body).not_to include("ZBETA")
    end
  end

  describe "search GET /search" do
    # Query a term both claims share ("swept") so the echoed query box can't itself
    # supply the distinctive removed token — only a real result would.
    it "returns the active match but never the removed one" do
      sign_in member
      get "/search", params: {q: "swept"}
      expect(response.body).to include("ZALPHA")
      expect(response.body).not_to include("ZBETA")
    end
  end

  describe "thread GET /hoojah/:slug" do
    it "hides a removed reply while the parent still renders" do
      sign_in member
      get "/hoojah/#{parent.slug}"
      expect(response.body).to include("ZPARENT")
      expect(response.body).to include("ZGAMMA")
      expect(response.body).not_to include("ZDELTA")
    end
  end

  describe "profile GET /u/:username" do
    it "excludes the removed claim from the Hoojahs tab and the counters" do
      get "/u/#{author.username}"
      expect(response.body).to include("ZALPHA")
      expect(response.body).not_to include("ZBETA")
      # @hoojahs_count = 1 active top-level (removed excluded);
      # @responses_count = 1 active reply (removed reply excluded).
      expect(response.body).to include("Hoojahs · 1")
      expect(response.body).to include("Responses · 1")
    end
  end

  describe "tag feed GET /t/:name" do
    it "excludes the removed claim and its count" do
      get "/t/swept"
      expect(response.body).to include("ZALPHA")
      expect(response.body).not_to include("ZBETA")
      expect(response.body).to include("1 hoojah tagged")
    end
  end

  describe "API index GET /api/v1/hoojah/index" do
    it "omits the removed claim from JSON" do
      get "/api/v1/hoojah/index"
      expect(response.body).to include("ZALPHA")
      expect(response.body).not_to include("ZBETA")
    end
  end

  describe "author lockout" do
    it "redirects the author away from their own removed hoojah with an alert" do
      sign_in author
      get "/hoojah/#{removed_top.slug}"
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("Not allowed.")
    end

    it "keeps the removed hoojah out of the author's own profile tab" do
      sign_in author
      get "/u/#{author.username}"
      expect(response.body).not_to include("ZBETA")
    end
  end

  describe "staff access (direct URL, not feeds)" do
    it "lets a moderator read the removed hoojah by direct URL" do
      sign_in moderator
      get "/hoojah/#{removed_top.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ZBETA")
    end
  end
end
