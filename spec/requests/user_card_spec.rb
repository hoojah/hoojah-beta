require "rails_helper"

# Slice B, Task 1: the hovercard body endpoint (GET /u/:username/card). layout:false;
# Standard fields for a visible user, a gated minimal whitelist for a private stranger
# (the SAME visible_to? gate as users#show). Guests may view public cards; unknown → 404.
RSpec.describe "User card", type: :request do
  it "renders the Standard card (full name, @username, counts, headline) to a signed-in viewer" do
    user = create(:user, username: "publicu", full_name: "Aisha Rahman", headline: "Debate enthusiast")
    sign_in create(:user)

    get "/u/publicu/card"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aisha Rahman")
    expect(response.body).to include("@publicu")
    # Standard-only marker: the headline is omitted from the gated whitelist.
    expect(response.body).to include("Debate enthusiast")
    # Counts read the counter-cache columns (self-wrapped follower chip + inline following).
    expect(response.body).to include(ActionView::RecordIdentifier.dom_id(user, :follower_count))
  end

  it "renders the Standard card to a GUEST for a public user (guests may view public cards)" do
    create(:user, username: "guestview", full_name: "Public Person", headline: "Open to all")

    get "/u/guestview/card"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Public Person")
    expect(response.body).to include("@guestview")
    expect(response.body).to include("Open to all")
  end

  it "renders the gated card (no headline/location/link) to a stranger of a private user" do
    create(:user, username: "privateu", full_name: "Hidden Hana", private: true,
      headline: "SECRET HEADLINE", location: "SECRET LOCATION", link: "https://secret.example.com")
    sign_in create(:user)

    get "/u/privateu/card"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Private account")
    expect(response.body).to include("Hidden Hana")
    expect(response.body).to include("@privateu")
    # The follow button is part of the gated whitelist.
    expect(response.body).to include("Follow")
    # The leak boundary: none of the content fields may appear.
    expect(response.body).not_to include("SECRET HEADLINE")
    expect(response.body).not_to include("SECRET LOCATION")
    expect(response.body).not_to include("secret.example.com")
  end

  it "renders the Standard card to an accepted follower of a private user" do
    owner = create(:user, username: "privfollowed", full_name: "Private Owner",
      private: true, headline: "FOLLOWER-VISIBLE HEADLINE")
    follower = create(:user)
    follower.active_follows.create!(followed: owner, status: :accepted)
    sign_in follower

    get "/u/privfollowed/card"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("FOLLOWER-VISIBLE HEADLINE")
    expect(response.body).not_to include("Private account")
  end

  it "renders the Standard card to the private user themself" do
    owner = create(:user, username: "privself", private: true, headline: "MY OWN HEADLINE")
    sign_in owner

    get "/u/privself/card"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("MY OWN HEADLINE")
    expect(response.body).not_to include("Private account")
  end

  it "returns 404 for an unknown username" do
    expect { get "/u/nobody-here/card" }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "carries no application layout (no navbar chrome)" do
    create(:user, username: "nolayout", full_name: "No Layout")

    get "/u/nolayout/card"

    expect(response).to have_http_status(:ok)
    # The shared navbar (rendered by the application layout) must be absent.
    expect(response.body).not_to include("id=\"navbar\"")
    expect(response.body).not_to include("<nav")
  end
end
