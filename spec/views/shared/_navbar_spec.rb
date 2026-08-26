require "rails_helper"

# Hoojah 2026, redesign Phase 0, Task 0.4 — a RESTYLE of `shared/_navbar`, not a
# behaviour change. Every link, the `<details>` avatar menu, the theme/scheme pill,
# and the unread-dot rules are unchanged; `spec/requests/navigation_spec.rb` is the
# regression net for that behaviour. This spec pins the 2026 visual deltas: the
# `bg-nav` wrapper, the filled trending button, and the tile avatar.
RSpec.describe "shared/_navbar", type: :view do
  def html
    render(partial: "shared/navbar").strip
  end

  def navbar
    Capybara.string(html)
  end

  def stub_signed_out
    allow(view).to receive_messages(user_signed_in?: false, current_user: nil)
  end

  def stub_signed_in(user)
    allow(view).to receive_messages(user_signed_in?: true, current_user: user)
  end

  it "wraps in the theme-aware bg-nav surface, not the old bg-card/border-gray-100" do
    stub_signed_out

    expect(navbar).to have_css("nav.bg-nav.backdrop-blur.border-hairline")
    expect(navbar).to have_no_css("nav.border-gray-100")
  end

  # `bg-card-2`/`text-neutral` are theme-aware tokens (see CLAUDE.md: never hardcode
  # stance/surface hex), so this is the 2026 filled-icon-button treatment, not a
  # concrete colour.
  it "gives the trending link a filled icon-button look, and keeps the label + route" do
    stub_signed_out

    expect(navbar).to have_css("a.bg-card-2.text-neutral.rounded-xl[href='#{trending_path}']", text: "Trending")
  end

  describe "signed in" do
    # A photo, deliberately: `ui/_avatar` falls back to the tile on its own whenever a
    # user has no photo, so a photoless stub would pass this example even if the navbar
    # never asked for `variant: :tile`. Giving the stub a photo is what proves the
    # navbar renders the TILE TREATMENT on purpose (Task 0.4), not the accidental
    # fallback (see `ui/_avatar` "variant: :tile … wins over the photo").
    let(:user) do
      build_stubbed(:user, full_name: "Maya Zaharudin", username: "mayaz",
        photo: "https://res.cloudinary.com/hoojah/image/upload/v1586909321/user_photo_2.gif")
    end

    before { stub_signed_in(user) }

    it "keeps the theme/scheme pill that drives the 2026 themes" do
      expect(navbar).to have_css("[data-controller='theme']")
      expect(navbar).to have_css("[data-action='theme#toggleTheme']")
      expect(navbar).to have_css("[data-action='theme#cycleScheme']")
    end

    it "places the avatar menu to the LEFT of the theme/scheme toggles" do
      # The left zone is a flex row; CSS `order` renders the user dropdown (order-1)
      # before the theme pill (order-2), so the avatar reads to the left of the
      # light/dark + scheme toggles whenever it is shown (signed in).
      expect(navbar).to have_css("details.order-1")
      expect(navbar).to have_css("[data-controller='theme'].order-2")
    end

    it "renders the menu summary avatar as the 2026 gradient tile, even though this user has a photo" do
      expect(navbar).to have_css("details summary span.avatar-tile.rounded-xl", text: "MZ")
      expect(navbar).to have_no_css("details summary img")
    end

    it "shows the unread pink dot when there are unread notifications" do
      allow(user).to receive(:unread_notifications_count).and_return(1)

      expect(navbar).to have_css("span[role='img'][aria-label='Unread notifications']")
    end

    it "shows no unread dot when there are none" do
      allow(user).to receive(:unread_notifications_count).and_return(0)

      expect(navbar).to have_no_css("span[role='img'][aria-label='Unread notifications']")
    end

    it "keeps the New Claim compose entry" do
      expect(navbar).to have_css("a[href='#{new_hujah_path}']", text: "New Claim")
    end

    it "shows no Login/Sign up links" do
      expect(navbar).to have_no_text("Login")
      expect(navbar).to have_no_text("Sign up")
    end
  end

  describe "signed out" do
    before { stub_signed_out }

    it "shows Login and Sign up" do
      expect(navbar).to have_css("a[href='#{new_user_session_path}']", text: "Login")
      expect(navbar).to have_css("a[href='#{new_user_registration_path}']", text: "Sign up")
    end

    it "renders no avatar menu" do
      expect(navbar).to have_no_css("details")
    end

    # 2026 three-zone navbar: New Claim is a member-only action, so it must NOT
    # render for guests — the guest right zone carries only Login + Sign up.
    it "does not render the New Claim compose entry" do
      expect(navbar).to have_no_css("a[href='#{new_hujah_path}']")
    end
  end
end
