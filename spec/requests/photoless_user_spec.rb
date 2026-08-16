require "rails_helper"

# `ui/_avatar` exists because `image_tag user.photo` RAISES on a blank photo, and
# spec/views/ui/avatar_spec.rb pins that behaviour thoroughly — for the PARTIAL.
# Nothing pinned the CALL SITES, so reverting any one of the hujah family's four
# avatars to `image_tag user.photo` would leave the whole suite green while putting
# the 500 straight back. These are the three screens where that 500 is worst: the
# feed (every signed-in and signed-out visitor), the single-hujah page, and compose.
#
# Reaching a photoless user needs `update_column`: `assign_random_photo` is an
# `after_create` callback, so the factory always backfills one. Production reaches
# the same state the ordinary way — `:photo` is permitted in `user_params`, so a user
# who clears it on their profile is one save away from this row.
RSpec.describe "A user with no photo", type: :request do
  let(:author) { create(:user, username: "photoless", full_name: "Siti Nurhaliza") }
  let(:responder) { create(:user, username: "alsophotoless", full_name: "Lim Guan Eng") }

  before do
    author.update_column(:photo, nil)
    responder.update_column(:photo, nil)
  end

  it "renders the feed rather than 500ing it for everyone" do
    create(:hujah, user: author, parent_id: nil)

    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Siti Nurhaliza")
  end

  # The show page renders the author's avatar in the byline AND the responder's in
  # every threaded child card, so one photoless responder is enough to break it even
  # when the author has a photo.
  it "renders a hoojah whose author and responder both lack one" do
    hujah = create(:hujah, user: author, parent_id: nil)
    create(:hujah, user: responder, parent_id: hujah.id, vote: 1)

    get "/hoojah/#{hujah.slug}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Lim Guan Eng")
  end

  # The composer draws `current_user`'s own 44px avatar, so this one only ever breaks
  # for the person who cleared their photo — which is exactly why it went unnoticed.
  it "renders the composer for the viewer who cleared their own photo" do
    sign_in author

    get "/hoojah/new"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("What&#39;s your hoojah?")
  end

  # The reply composer additionally renders `hujahs/_parent_card`, and reaches the
  # parent author's name through it.
  it "renders the reply composer" do
    parent = create(:hujah, user: responder, parent_id: nil)
    sign_in author

    get "/hoojah/#{parent.slug}/respond"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Lim Guan Eng")
  end
end
