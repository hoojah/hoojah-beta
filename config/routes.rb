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
  # HTML voting (Task 4.3). Declared here alongside the feed so `hujah_votes_path`
  # resolves when `_vote_bars` renders inside the card in the feed AND the show page.
  post "/hoojah/:slug/votes", to: "votes#create", as: :hujah_votes
end
