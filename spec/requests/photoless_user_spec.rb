require "rails_helper"

# `ui/_avatar` exists because `image_tag user.photo` RAISES on a blank photo, and
# spec/views/ui/avatar_spec.rb pins that behaviour thoroughly — for the PARTIAL.
# Nothing pinned the CALL SITES, so reverting any one of them to `image_tag
# user.photo` would leave the whole suite green while putting the 500 straight back.
#
# Slice 9 Task 4.3 covered the hujah family (feed, single hujah, both composers).
# Task 4.4 moved five more call sites in the SOCIAL family — `users/_profile_header`,
# `_gated_header`, `_profile_edit`, `_user_hujah` and `_user_row` — so the second
# describe block below covers those. Two of them are worse than a normal 500: the
# followers list breaks for every visitor because of ONE photoless follower, and the
# edit dialog breaks only for the person who cleared their photo, i.e. exactly the
# user who needs it to set a new one.
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

  # Slice 9 Task 4.4 — the five social call sites. Each example hits a DIFFERENT
  # partial; they are not variations on one screen. Deleting any single
  # `render "ui/avatar"` below should turn exactly one of them red.
  describe "on the social screens" do
    # `_profile_header` (96px) — and `_user_hujah` (32px) for every hoojah listed
    # underneath it, which is why this example posts one.
    it "renders their own public profile and the hoojah list on it" do
      create(:hujah, user: author, parent_id: nil, body: "a photoless take")

      get "/u/photoless"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("a photoless take")
    end

    # `_user_row` (40px), twice over: one photoless follower is enough to take the
    # list down for everyone who opens it, including the profile owner.
    it "renders the followers and following lists that contain them" do
      responder.active_follows.create!(followed_id: author.id, status: :accepted)

      get "/u/photoless/followers"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lim Guan Eng")

      get "/u/alsophotoless/following"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Siti Nurhaliza")
    end

    # `_gated_header` is a SEPARATE partial from `_profile_header` with its own
    # avatar line, reachable only when the target is private and the viewer is not an
    # accepted follower — so the un-gated example above cannot cover it.
    it "renders the gated header of a private photoless account" do
      author.update!(private: true)
      sign_in responder

      get "/u/photoless"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This account is private")
    end

    # `_profile_edit`. The dialog is in the DOM on the owner's own profile page, so
    # this 500s the owner out of the one screen that could fix their photo.
    it "renders the edit dialog for the owner who cleared their own photo" do
      sign_in author

      get "/u/photoless"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit your profile")
    end

    # The no-JS fallback page renders the same header + dialog outside the profile
    # screen, and reaches `_profile_edit` by a second route.
    it "renders the no-JS profile edit page" do
      sign_in author

      get "/u/photoless/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit your profile")
    end
  end

  # Slice 9 Task 4.5 moved the debate family's ONE avatar call site,
  # `debates/_debate_turn` — the last live `image_tag user.photo` anywhere in the app.
  #
  # This example covers the REQUEST path only, and that is the lesser half. The same
  # partial is also rendered from `Debate#post_turn`'s `broadcast_append_later_to`,
  # where the identical raise happens inside an ActiveJob: no 500 reaches anybody, the
  # transcript simply stops updating live, and the failure is visible only in the job
  # log. Nothing a request spec does can enter that path, so
  # spec/models/debate_broadcast_spec.rb carries the matching example. Both are needed;
  # neither substitutes for the other.
  describe "in a debate transcript" do
    it "renders a transcript containing a photoless participant's turn" do
      debate = create(:debate, challenger: author, opponent: responder, status: :active)
      debate.post_turn(by: author, body: "Tabs are one keystroke.")
      sign_in responder

      get "/debates/#{debate.slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tabs are one keystroke.")
      expect(response.body).to include("Siti Nurhaliza")
    end
  end
end
