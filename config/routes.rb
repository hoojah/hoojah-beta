Rails.application.routes.draw do
  devise_for :users,
    controllers: {registrations: "users/registrations"},
    path: "",
    path_names: {sign_in: "login", sign_out: "logout", sign_up: "signup"}

  namespace :api do
    namespace :v1 do
      get "hoojah/index", to: "hujahs#index"
      post "hoojah/create", to: "hujahs#create"
      get "/hoojah/:slug", to: "hujahs#show"
      delete "/hoojah/destroy/:slug", to: "hujahs#destroy"
      get "/hoojah/new", to: "hujahs#new"

      post "votes/create", to: "votes#create"

      get "/:username", to: "users#show"
      post ":username/update", to: "users#update"

      post "flags/create", to: "flags#create"

      get "/:username/notifications", to: "notifications#index"
      put "/:username/notifications/:id", to: "notifications#update"
      delete "/:username/notifications/:id", to: "notifications#destroy"
    end
  end

  # HTML (Hotwire) screens — the server-rendered replacement for the legacy SPA.
  root "hujahs#index"
  # Compose / respond (Task 2.1). `/hoojah/new` is the top-level compose entry;
  # `/hoojah/:slug/respond` seeds the form with a parent (reply). Both hit #new.
  get "/hoojah/new", to: "hujahs#new", as: :new_hujah
  get "/hoojah/:slug/respond", to: "hujahs#new", as: :respond_hujah
  post "/hoojah", to: "hujahs#create"
  get "/hoojah/:slug", to: "hujahs#show", as: :hujah
  # Profile (Task 3.2). Public view at /u/:username; owner-only edit/update.
  # `:username` (not id/slug) mirrors the legacy SPA `/api/v1/:username` shape.
  get "/u/:username", to: "users#show", as: :profile
  get "/u/:username/edit", to: "users#edit", as: :edit_profile
  patch "/u/:username", to: "users#update"
  # Follow / unfollow (Slice 3, Task 2.1). Main routes (NOT Api::V1) so CSRF stays
  # on — `button_to` carries the authenticity token. Turbo-Stream flips the button
  # + follower-count chip in place.
  post "/u/:username/follow", to: "follows#create", as: :follow_user
  delete "/u/:username/follow", to: "follows#destroy", as: :unfollow_user
  # Public followers / following lists (Slice 3, Task 2.2).
  get "/u/:username/followers", to: "users#followers", as: :user_followers
  get "/u/:username/following", to: "users#following", as: :user_following
  # HTML voting (Task 4.3). Declared here alongside the feed so `hujah_votes_path`
  # resolves when `_vote_bars` renders inside the card in the feed AND the show page.
  post "/hoojah/:slug/votes", to: "votes#create", as: :hujah_votes
  # Flag (Task 5.1). POST a flag against a hoojah from the native <dialog> on the
  # show page. Records under current_user; responds as a Turbo Stream that closes
  # the dialog + shows a confirmation.
  post "/hoojah/:slug/flags", to: "flags#create", as: :hujah_flags
  # Debate (Slice 4). One-on-one turn-based debate escalated from an argument.
  # RESTful member actions only (no generic PATCH /debates/:slug); every write
  # derives the actor from `current_user`. `create` is nested under the hoojah so
  # the argument can be validated against the URL's :slug. Turns POST to the debate.
  post "/hoojah/:slug/debates", to: "debates#create"
  get "/debates/:slug", to: "debates#show", as: :debate
  patch "/debates/:slug/accept", to: "debates#accept", as: :accept_debate
  patch "/debates/:slug/decline", to: "debates#decline", as: :decline_debate
  patch "/debates/:slug/conclude", to: "debates#conclude", as: :conclude_debate
  post "/debates/:slug/turns", to: "debate_turns#create", as: :debate_turns
  # Notifications (Task 4.1). Always the current user's own list (policy_scope, no
  # username in the URL). PATCH marks read + redirects to the hoojah; DELETE removes
  # the card via Turbo-Stream.
  # Analytics dashboard (Slice 5, Part B). Owner-only by construction: always the
  # current user's own aggregates (no username in the URL, like /notifications).
  get "/dashboard", to: "analytics#show", as: :dashboard
  # Trending (Slice 6). Public, cached top-level hoojahs by HN-decayed activity.
  # Rendered both as a standalone page and as the feed's lazy turbo_frame sidebar.
  get "/trending", to: "trending#index", as: :trending
  get "/notifications", to: "notifications#index", as: :notifications
  patch "/notifications/:id", to: "notifications#update", as: :notification
  delete "/notifications/:id", to: "notifications#destroy"
end
