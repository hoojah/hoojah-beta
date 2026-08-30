require "rails_helper"

# Issue #18 — the admin listings: an all-users index and an all-hoojahs index,
# both READ-ONLY and staff-gated by the headless AdminPolicy (can_moderate? — the
# app's single capability gate). Distinct from /moderation (the flag queue) and
# /dashboard (the user's OWN analytics). Staff are the one audience that reads
# private accounts and removed/non-public content, so neither list is swept.
RSpec.describe "Admin listings", type: :request do
  let(:member) { create(:user) }
  let(:moderator) { create(:user, :moderator) }
  let(:admin) { create(:user, :admin) }

  describe "GET /admin/users" do
    it "redirects an anonymous visitor to login" do
      get "/admin/users"
      expect(response).to redirect_to(new_user_session_path)
    end

    it "denies a plain member with the Pundit alert (not 200)" do
      sign_in member
      get "/admin/users"
      expect(response).not_to have_http_status(:ok)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Not allowed.")
    end

    it "renders for a moderator" do
      sign_in moderator
      get "/admin/users"
      expect(response).to have_http_status(:ok)
    end

    it "renders for an admin" do
      sign_in admin
      get "/admin/users"
      expect(response).to have_http_status(:ok)
    end

    it "lists a private account's username — staff see private users" do
      create(:user, username: "secretive", private: true)
      sign_in moderator
      get "/admin/users"

      expect(response.body).to include("secretive")
    end
  end

  describe "GET /admin/hoojahs" do
    it "redirects an anonymous visitor to login" do
      get "/admin/hoojahs"
      expect(response).to redirect_to(new_user_session_path)
    end

    it "denies a plain member with the Pundit alert (not 200)" do
      sign_in member
      get "/admin/hoojahs"
      expect(response).not_to have_http_status(:ok)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Not allowed.")
    end

    it "renders for a moderator" do
      sign_in moderator
      get "/admin/hoojahs"
      expect(response).to have_http_status(:ok)
    end

    it "renders for an admin" do
      sign_in admin
      get "/admin/hoojahs"
      expect(response).to have_http_status(:ok)
    end

    it "includes a removed hujah's excerpt — the list is NOT not_removed-swept" do
      removed = create(:hujah, body: "Removed but staff-visible claim")
      removed.update!(moderation_status: :removed)
      sign_in moderator
      get "/admin/hoojahs"

      expect(response.body).to include("Removed but staff-visible claim")
    end

    it "includes a followers_only hujah's excerpt — the list is NOT visibility-filtered" do
      create(:hujah, body: "Followers only claim here", visibility: :followers_only)
      sign_in moderator
      get "/admin/hoojahs"

      expect(response.body).to include("Followers only claim here")
    end
  end

  # pagy(:countless, limit: 25): 26 hujahs => page 1 carries a "Load more" link at
  # ?page=2, and page 2 renders the remainder (a plain full-page GET, no turbo_stream).
  describe "pagination" do
    it "paginates the hoojahs list at 25 per page with a Load more link" do
      26.times { |i| create(:hujah, body: "Paginated claim number #{i}") }
      sign_in moderator

      get "/admin/hoojahs"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(admin_hujahs_path(page: 2))

      get admin_hujahs_path(page: 2)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "navbar entry" do
    it "shows the admin links for a staff user" do
      sign_in admin
      get "/"
      expect(response.body).to include(admin_users_path)
      expect(response.body).to include(admin_hujahs_path)
    end

    it "hides the admin links from a plain member" do
      sign_in member
      get "/"
      expect(response.body).not_to include(admin_users_path)
      expect(response.body).not_to include(admin_hujahs_path)
    end
  end
end
