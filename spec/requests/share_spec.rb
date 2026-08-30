require "rails_helper"

RSpec.describe "Share menu", type: :request do
  let(:hujah) { create(:hujah) }

  it "renders server-side share intent links on the show page (works with no JS)" do
    get "/hoojah/#{hujah.slug}"
    expect(response).to have_http_status(:ok)

    # The URL half of the share menu now routes through the short link /s/:code
    # (issue #31) rather than the raw hoojah URL. The share TEXT stays frozen.
    short_url = short_link_url(ShortLink.for(hujah).code, host: "www.example.com")
    encoded_url = CGI.escape(short_url)

    # One <a href> per platform — always present, no JavaScript required.
    expect(response.body).to include("https://wa.me/?text=")           # WhatsApp
    expect(response.body).to include("https://x.com/intent/tweet")     # X
    expect(response.body).to include("https://t.me/share/url")         # Telegram
    expect(response.body).to include("https://www.reddit.com/submit")  # Reddit
    expect(response.body).to include("https://www.facebook.com/sharer/sharer.php?u=#{encoded_url}") # Facebook
    expect(response.body).to include("mailto:")                        # Email

    # The absolute short URL is threaded into the share targets, and it is a
    # 7-char opaque /s/:code — never the internal hoojah path.
    expect(response.body).to include(encoded_url)
    expect(response.body).to match(%r{/s/[A-Za-z0-9]{7}})
    expect(response.body).to include(%(data-share-url-value="#{short_url}"))
  end

  it "renders a hidden native-share button wired to the share controller" do
    get "/hoojah/#{hujah.slug}"

    expect(response.body).to include('data-controller="share"')
    expect(response.body).to include('data-action="share#share"')
    expect(response.body).to include('data-share-target="button"')
    expect(response.body).to include("hidden")
  end
end
