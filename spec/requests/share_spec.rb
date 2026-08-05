require "rails_helper"

RSpec.describe "Share menu", type: :request do
  let(:hujah) { create(:hujah) }

  it "renders server-side share intent links on the show page (works with no JS)" do
    get "/hoojah/#{hujah.slug}"
    expect(response).to have_http_status(:ok)

    encoded_url = CGI.escape("http://www.example.com/hoojah/#{hujah.slug}")

    # One <a href> per platform — always present, no JavaScript required.
    expect(response.body).to include("https://wa.me/?text=")           # WhatsApp
    expect(response.body).to include("https://x.com/intent/tweet")     # X
    expect(response.body).to include("https://t.me/share/url")         # Telegram
    expect(response.body).to include("https://www.reddit.com/submit")  # Reddit
    expect(response.body).to include("https://www.facebook.com/sharer/sharer.php?u=#{encoded_url}") # Facebook
    expect(response.body).to include("mailto:")                        # Email

    # The absolute hoojah URL is threaded into the share targets.
    expect(response.body).to include(encoded_url)
  end

  it "renders a hidden native-share button wired to the share controller" do
    get "/hoojah/#{hujah.slug}"

    expect(response.body).to include('data-controller="share"')
    expect(response.body).to include('data-action="share#share"')
    expect(response.body).to include('data-share-target="button"')
    expect(response.body).to include("hidden")
  end
end
