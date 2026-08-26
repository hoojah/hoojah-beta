require "rails_helper"

# Cuprite (headless Chrome) coverage for the Slice B user hovercard.
#
# The controller (app/javascript/controllers/hovercard_controller.js) attaches to
# every `ui/_user_link` anchor. On a fine-pointer hover/focus it fetches the
# layout-less card body (users#card, `user_card_path`) after a ~400ms delay and
# shows it in a SINGLE floating panel appended to <body>; a plain click just
# navigates the underlying <a>.
#
# The panel is a module-scoped singleton reused by every trigger, so there is only
# ever ONE panel element. Its chrome class combination `.fixed.w-72.z-50` is unique
# in the app (nothing else uses w-72), so it doubles as the panel selector.
# `opacity-100` is the shown state — Capybara treats opacity:0 as "visible", so we
# assert on the class, never on Capybara visibility, to distinguish shown vs hidden.
RSpec.describe "User hovercard", type: :system, js: true do
  # The one shared panel (`.fixed.w-72.z-50`, unique in the app) and its shown state
  # (`opacity-100`). `let`, not constants, to avoid Lint/ConstantDefinitionInBlock.
  let(:panel) { ".fixed.w-72.z-50" }
  let(:shown) { ".fixed.w-72.z-50.opacity-100" }

  # A public author whose Standard card carries a distinctive headline (the marker
  # that a Standard — not gated — card rendered) and non-colliding, digit-only
  # counts read straight from the counter-cache columns.
  def public_author(username)
    create(:user, username: username, full_name: "Ada Author",
      headline: "Builds bridges in Klang",
      followers_count: 4, following_count: 9)
  end

  it "shows the card after the hover delay with the author's name, headline and counts" do
    author = public_author("ada")
    create(:hujah, user: author, body: "A claim about durian pricing in Bangi")
    login_as_system(create(:user))
    visit "/"

    # Nothing is shown before the hover (the panel is created lazily on first show).
    expect(page).to have_no_css(shown)

    find("a[href='/u/ada']", match: :first).hover

    expect(page).to have_css(shown, wait: 3)
    within(panel) do
      expect(page).to have_content("Ada Author")
      expect(page).to have_content("Builds bridges in Klang") # Standard-only field
      expect(page).to have_content("4") # followers_count (counter-cache column)
      expect(page).to have_content("9") # following_count (counter-cache column)
    end

    # Single-shared-panel invariant: exactly one card element in the DOM.
    expect(page).to have_css(panel, count: 1)
  end

  it "keeps the card open while the cursor rests on it, and hides it after leaving both" do
    author = public_author("ada")
    create(:hujah, user: author, body: "A claim about durian pricing in Bangi")
    login_as_system(create(:user))
    visit "/"

    find("a[href='/u/ada']", match: :first).hover
    expect(page).to have_css(shown, wait: 3)

    # The keep-open bridge: the panel's own mouseenter cancels the pending hide, so
    # moving the cursor trigger->card keeps it shown. (Cuprite cannot script a smooth
    # cursor path across the gap between the two, so we hover the panel directly —
    # which fires the same mouseenter the real bridge relies on.)
    find(panel).hover
    expect(page).to have_css(shown)

    # Leaving both: hover a neutral element well above the panel (the feed tab sits
    # above the byline, so the panel — anchored below the byline — never overlaps it).
    # After the ~200ms grace with the pointer over neither trigger nor panel, it hides.
    find(:link, "Everyone").hover
    expect(page).to have_no_css(shown, wait: 3)
  end

  it "dismisses the card on Escape" do
    author = public_author("ada")
    create(:hujah, user: author, body: "A claim about durian pricing in Bangi")
    login_as_system(create(:user))
    visit "/"

    trigger = find("a[href='/u/ada']", match: :first)
    trigger.hover
    expect(page).to have_css(shown, wait: 3)

    # keydown Escape on the (focusable) anchor bubbles to the document listener.
    trigger.send_keys(:escape)
    expect(page).to have_no_css(shown, wait: 2)
  end

  it "dismisses the card on a click away from the trigger and panel" do
    author = public_author("ada")
    create(:hujah, user: author, body: "A claim about durian pricing in Bangi")
    login_as_system(create(:user))
    visit "/"

    find("a[href='/u/ada']", match: :first).hover
    expect(page).to have_css(shown, wait: 3)

    # A click on a neutral, non-navigating control outside both trigger and panel
    # (the collapsed composer button) trips the document click-away listener.
    find("button[data-composer-target='collapsed']").click
    expect(page).to have_no_css(shown, wait: 2)
  end

  it "navigates to /u/:username when the byline is clicked (the dead '#' links are gone)" do
    author = public_author("ada")
    create(:hujah, user: author, body: "A claim about durian pricing in Bangi")
    login_as_system(create(:user))
    visit "/"

    # The feed byline used to link to a dead '#' placeholder; it is now a real anchor.
    find("a[href='/u/ada']", match: :first).click
    expect(page).to have_current_path("/u/ada")
  end

  it "shows the gated minimal card (Private account, no headline/location) for a private stranger" do
    # A private author appears in a PUBLIC user's followers list — the one organic
    # surface where a stranger sees a private user's byline (visibility scopes hide
    # them from feed/search). Hovering it fetches the GATED card body.
    private_author = create(:user, username: "priv", full_name: "Pat Private",
      headline: "SECRET HEADLINE", location: "Secret City", private: true)
    host = create(:user, username: "host") # public
    private_author.active_follows.create!(followed: host, status: :accepted)
    # Pin the displayed counts AFTER the follow so the follow callback's counter
    # bumps don't move the numbers we assert on.
    private_author.update_columns(followers_count: 2, following_count: 5)

    login_as_system(create(:user)) # a signed-in stranger (not an accepted follower)
    visit "/u/host/followers"

    find("a[href='/u/priv']", match: :first).hover
    expect(page).to have_css(shown, wait: 3)
    within(panel) do
      expect(page).to have_content("Pat Private")
      expect(page).to have_content("Private account")
      expect(page).to have_button("Follow") # follow control renders for a signed-in non-owner
      expect(page).to have_content("2") # followers_count
      expect(page).to have_content("5") # following_count

      # The leak boundary: the gated card OMITS headline and location.
      expect(page).not_to have_content("SECRET HEADLINE")
      expect(page).not_to have_content("Secret City")
    end
  end

  it "shows the Standard card to a signed-out guest hovering a public author" do
    author = public_author("ada")
    create(:hujah, user: author, body: "A claim about durian pricing in Bangi")
    # No login — guests may view public cards.
    visit "/"

    find("a[href='/u/ada']", match: :first).hover
    expect(page).to have_css(shown, wait: 3)
    within(panel) do
      expect(page).to have_content("Ada Author")
      expect(page).to have_content("Builds bridges in Klang") # Standard-only field
      expect(page).not_to have_content("Private account")
    end
  end

  it "exposes a real profile href so touch / JS-off clients still navigate" do
    # Degradation contract. Emulating `pointer: coarse` in Cuprite is unreliable, so
    # rather than assert the media-query no-op branch we assert the contract that
    # makes the no-op safe: every byline is a genuine <a href> to the profile (also
    # carrying the hovercard controller) — a touch tap or a JS-off client navigates.
    author = public_author("ada")
    create(:hujah, user: author, body: "A claim about durian pricing in Bangi")
    visit "/"

    expect(page).to have_css("a[href='/u/ada'][data-controller='hovercard']")
  end
end
