require "rails_helper"

# Cuprite (headless Chrome) coverage for the share menu. The intent links
# (WhatsApp / X / Telegram / Reddit / Facebook / Email) are always server-rendered
# and work with JS off. share_controller.js only progressively enhances: it unhides
# a native "Share…" button when navigator.share exists. Recent headless Chrome DOES
# expose navigator.share, so the native button's visibility is Chrome-version
# dependent — we assert the always-present fallback links plus that the native button
# is present and wired, not its visibility.
RSpec.describe "Sharing a hoojah", type: :system, js: true do
  let(:author) { create(:user, username: "author") }
  let(:hujah) { create(:hujah, user: author, body: "Share me around") }

  it "renders the fallback intent links and the wired native-share button" do
    visit "/hoojah/#{hujah.slug}"

    find("summary[aria-label='Share this hoojah']").click

    # The URL half now routes through the short link /s/:code (issue #31): the raw
    # short URL is on data-share-url-value; the social hrefs carry it CGI-escaped.
    # `~=` (token match) rather than `=`: the <details> now carries TWO controllers
    # ("share dropdown" — the second dismisses the menu on an outside tap), so an
    # exact-value selector no longer matches.
    expect(page).to have_selector(
      %([data-controller~="share"][data-share-url-value*="/s/"])
    )

    within('[data-controller~="share"]') do
      expect(page).to have_link("WhatsApp", href: /wa\.me/)
      expect(page).to have_link("X", href: /x\.com\/intent\/tweet/)
      expect(page).to have_link("Telegram", href: /t\.me\/share/)
      expect(page).to have_link("Reddit", href: /reddit\.com\/submit/)
      expect(page).to have_link("Facebook", href: /facebook\.com\/sharer/)
      expect(page).to have_link("Email", href: /\Amailto:/)

      # Native OS-share button is present and wired to share#share, whether or not
      # this Chrome build unhides it (depends on navigator.share support).
      expect(page).to have_button("Share…", visible: :all)
      expect(page).to have_selector(
        "[data-share-target='button'][data-action='share#share']",
        visible: :all
      )
    end
  end
end
