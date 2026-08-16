require "rails_helper"

# Slice 9 / Task 4.1 — the things that actually *changed behaviour* when the navigation
# family moved onto the design system. The rest of that task is a restyle, and the
# existing suite is its regression net.
RSpec.describe "Navbar", type: :request do
  let(:user) { create(:user, username: "mayaz", full_name: "Maya Zaharudin") }

  # It rendered `link_to "Your profile", "#"` — a menu row that looked live, was
  # keyboard-focusable, and went nowhere. Every signed-in page carries this bar.
  it "points 'Your profile' at the signed-in user's own profile" do
    sign_in user
    get "/"

    expect(response.body).to include(%(href="#{profile_path(user.username)}"))
    expect(response.body).not_to match(/<a[^>]*href="#"[^>]*>\s*Your profile/)
  end

  # The navbar called `image_tag current_user.photo` directly. `photo` is nullable —
  # `photo_from_cloudinary` returns early on a blank value and `assign_random_photo` is
  # `after_create` only, so an account that later clears its photo keeps it blank — and
  # `image_tag nil` raises. Because this partial is on every signed-in screen, that one
  # missing avatar took down the whole app for that user, not one page.
  #
  # `update_column`, not `update`: the callback that would backfill the photo has already
  # run, but the validation still has to be bypassed to reach the state a real user
  # reaches through `user_params`.
  context "when the signed-in user has no photo" do
    before { user.update_column(:photo, nil) }

    it "renders the page instead of 500ing on `image_tag nil`" do
      sign_in user
      get "/"

      expect(response).to have_http_status(:ok)
    end

    it "falls back to initials labelled with the person's name, per the design system" do
      sign_in user
      get "/"

      expect(response.body).to include(%(aria-label="Maya Zaharudin"))
      expect(response.body).to include("MZ")
    end
  end
end

# The feed tabs signalled the showing scope with colour alone — indigo text plus an
# indigo underline. `aria-current="page"` states it, which is what a screen reader and
# any colour-blind viewer need. The visual treatment is unchanged.
RSpec.describe "Feed tabs", type: :request do
  it "marks Everyone as the current scope on the default feed" do
    get "/"

    expect(response.body).to match(/<a[^>]*aria-current="page"[^>]*>Everyone/)
  end

  it "moves the marker to Following when that scope is showing" do
    sign_in create(:user)
    get "/", params: {filter: "following"}

    expect(response.body).to match(/<a[^>]*aria-current="page"[^>]*>Following/)
    expect(response.body).not_to match(/<a[^>]*aria-current="page"[^>]*>Everyone/)
  end

  # A signed-out visitor has no Following tab at all, so `?filter=following` leaves the
  # global feed showing — the marker has to agree with that, not with the query string.
  it "keeps the marker on Everyone for a signed-out ?filter=following request" do
    get "/", params: {filter: "following"}

    expect(response.body).to match(/<a[^>]*aria-current="page"[^>]*>Everyone/)
  end
end
