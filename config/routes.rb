Rails.application.routes.draw do
  # Container health check (Slice 10b). Rails 8 generates this in `rails new`; this
  # app predates it, having been upgraded from Rails 6. Coolify polls it to decide a
  # container is live — without it the deploy either never goes healthy or goes
  # healthy instantly and wrongly. `rails/health#show` returns 200 once the app has
  # booted and 500 if boot raised, which is exactly the signal the proxy needs.
  #
  # Two things had to be arranged around it, both in config/environments/production.rb:
  # `config.hosts` (the probe arrives on the container's internal address, not
  # APP_HOST) and `force_ssl` (the probe is plain HTTP inside the Docker network).
  # See the `host_authorization` and `ssl_options` comments there.
  get "/up", to: "rails/health#show", as: :rails_health_check

  # Branded error pages (2026). In production config.exceptions_app = routes sends an
  # unhandled 404/422/500 here so users get the app shell instead of Rails' default
  # static page. `via: :all` because the failing request can carry any verb.
  match "/404", to: "errors#show", via: :all, defaults: {status: 404}
  match "/422", to: "errors#show", via: :all, defaults: {status: 422}
  match "/500", to: "errors#show", via: :all, defaults: {status: 500}

  devise_for :users,
    controllers: {
      registrations: "users/registrations",
      omniauth_callbacks: "users/omniauth_callbacks"
    },
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
  # Delete a hoojah (HTML/Turbo twin of Api::V1::HujahsController#destroy). A WRITE
  # action, so it lives on a MAIN route (CSRF enforced — `button_to method: :delete`
  # carries the token), never under Api::V1. Owner-only via HujahPolicy#destroy?, and
  # refused when the hoojah has replies or debates — the same "moderation write on a
  # slug" shape as `delete "/moderation/:slug/remove"` below. No `as:` — the named
  # `hujah_path(slug)` from the GET above already resolves the DELETE.
  delete "/hoojah/:slug", to: "hujahs#destroy"
  # Profile (Task 3.2). Public view at /u/:username; owner-only edit/update.
  # `:username` (not id/slug) mirrors the legacy SPA `/api/v1/:username` shape.
  get "/u/:username", to: "users#show", as: :profile
  # Hovercard body (Slice B). Read-only → main route (NOT Api::V1) so CSRF strategy is
  # unchanged; #card calls skip_authorization like users#show. layout:false partial fetched
  # by hovercard_controller.js on hover. :username, not id (no friendly_id on User).
  get "/u/:username/card", to: "users#card", as: :user_card
  get "/u/:username/edit", to: "users#edit", as: :edit_profile
  patch "/u/:username", to: "users#update"
  # Follow / unfollow (Slice 3, Task 2.1). Main routes (NOT Api::V1) so CSRF stays
  # on — `button_to` carries the authenticity token. Turbo-Stream flips the button
  # + follower-count chip in place.
  post "/u/:username/follow", to: "follows#create", as: :follow_user
  delete "/u/:username/follow", to: "follows#destroy", as: :unfollow_user
  # Remove a follower (2026 follow gaps): the FOLLOWED user severs an accepted
  # follow pointed at them. :username is the FOLLOWER being removed — the mirror
  # image of DELETE /u/:username/follow, where :username is the followed target.
  delete "/u/:username/follower", to: "follows#remove_follower", as: :remove_follower
  # Public followers / following lists (Slice 3, Task 2.2).
  get "/u/:username/followers", to: "users#followers", as: :user_followers
  get "/u/:username/following", to: "users#following", as: :user_following
  # Follow requests (Slice 7b). Accept (PATCH) / decline (DELETE) a pending follow —
  # only the followed user may act (FollowRequestPolicy). Managed from the
  # follow_request notification card; the standalone inbox page is deferred. `:id`
  # is the Follow id; both verbs share the path so only PATCH is named.
  # Pending follow-requests inbox (2026 follow gaps). Own-resource surface: no
  # username in the URL — always the signed-in user's own pending passive follows
  # (like /notifications, /blocks). MAIN route (CSRF on) — its rows carry the
  # accept/decline button_to's. Static "/follow_requests" cannot be shadowed by
  # the "/follow_requests/:id" routes below (segment count differs), so order is
  # irrelevant — kept together for legibility.
  get "/follow_requests", to: "follow_requests#index", as: :follow_requests
  patch "/follow_requests/:id", to: "follow_requests#update", as: :follow_request
  delete "/follow_requests/:id", to: "follow_requests#destroy"
  # Block / unblock (Slice 7). Main routes (NOT Api::V1) so CSRF stays on. Bidirectional
  # block: rejects interactions at the policy layer + removes reciprocal follows.
  post "/u/:username/block", to: "blocks#create", as: :block_user
  delete "/u/:username/block", to: "blocks#destroy", as: :unblock_user
  # Current user's blocked-users list (no username in the URL — always own list).
  get "/blocks", to: "blocks#index", as: :blocks
  # Moderator review queue + actions (2026 moderation). Staff-only via the headless
  # ModerationPolicy; own-list style (no id in the index URL — the queue is global,
  # not user-scoped). HTML/Turbo WRITE actions, so they live on MAIN routes (CSRF
  # enforced), never under Api::V1. :slug is the flagged hujah's friendly_id.
  get "/moderation", to: "moderation#index", as: :moderation
  patch "/moderation/:slug/dismiss", to: "moderation#dismiss", as: :dismiss_moderation
  delete "/moderation/:slug/remove", to: "moderation#remove", as: :remove_moderation
  post "/moderation/:slug/warn", to: "moderation#warn", as: :warn_moderation
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
  # `new` (2026 Phase 3.2) is the create PAGE — rounds picker + opening argument —
  # that replaced the old stance-only <dialog>; same nesting, same reason.
  get "/hoojah/:slug/debates/new", to: "debates#new", as: :new_hujah_debate
  post "/hoojah/:slug/debates", to: "debates#create"
  get "/debates/:slug", to: "debates#show", as: :debate
  patch "/debates/:slug/accept", to: "debates#accept", as: :accept_debate
  patch "/debates/:slug/decline", to: "debates#decline", as: :decline_debate
  patch "/debates/:slug/conclude", to: "debates#conclude", as: :conclude_debate
  post "/debates/:slug/turns", to: "debate_turns#create", as: :debate_turns
  # Extend by one round at the closing-round boundary (Slice 9). The controller
  # action is `extend_rounds`, not `extend` — `extend` would shadow Object#extend
  # on the controller instance.
  post "/debates/:slug/extend", to: "debates#extend_rounds", as: :extend_debate
  # Spectator verdict on a concluded debate (Slice 8). One immutable vote per
  # visible spectator; the tally is compute-on-read.
  post "/debates/:slug/verdicts", to: "debate_verdicts#create", as: :debate_verdicts
  # Notifications (Task 4.1). Always the current user's own list (policy_scope, no
  # username in the URL). PATCH marks read + redirects to the hoojah; DELETE removes
  # the card via Turbo-Stream.
  # Analytics dashboard (Slice 5, Part B). Owner-only by construction: always the
  # current user's own aggregates (no username in the URL, like /notifications).
  get "/dashboard", to: "analytics#show", as: :dashboard
  # Trending (Slice 6). Public, cached top-level hoojahs by HN-decayed activity.
  # Rendered both as a standalone page and as the feed's lazy turbo_frame sidebar.
  get "/trending", to: "trending#index", as: :trending
  # Hashtag feed (2026). Public, countless-paginated top-level claims carrying :name
  # (canonical lower-cased). A hand-written path (no `resources`) addressed by tag
  # name — not id — like the rest of the app; mirrors the feed's per-post visibility.
  get "/t/:name", to: "tags#show", as: :tag
  # Search (2026 Phase 2.2). Public, read-only — a MAIN route (NOT Api::V1) so CSRF
  # stays on for the app's writes elsewhere; this action never writes. Results are
  # filtered through Hujah.visible_to / User.visible_to (SearchController), so it
  # can never surface content a normal feed/profile visit wouldn't already show.
  get "/search", to: "search#index", as: :search
  # Short share links (2026). /s/:code 301s to the stored INTERNAL path only — ShortLink
  # validates target_path against /hoojah|/debates, so this can never be an open redirect.
  # Public + unauthenticated: the redirect target enforces its own visibility; an opaque
  # code reveals nothing. MAIN route (never Api::V1); addressed by opaque code, not a slug.
  get "/s/:code", to: "short_links#show", as: :short_link
  # Public informational pages (2026). Static, no auth — anyone (signed out included)
  # can read the FAQ and the legal pages. MAIN routes (not Api::V1); they never write,
  # so CSRF posture is irrelevant. Addressed by plain path, not a record slug.
  # About tells newcomers what Hoojah is; Tutorials is the getting-started guide. Both
  # are static, no-auth siblings of the pages below — same posture, plain path, no slug.
  get "/about", to: "pages#about", as: :about
  get "/tutorials", to: "pages#tutorials", as: :tutorials
  get "/faq", to: "pages#faq", as: :faq
  get "/privacy", to: "pages#privacy", as: :privacy
  get "/terms", to: "pages#terms", as: :terms
  get "/notifications", to: "notifications#index", as: :notifications
  # Scope-only mark-all-read (Task 4.1) — no id/ids param, so there is nothing here
  # for a forged param to select; it can only ever touch the signed-in user's own
  # unread rows via policy_scope. Declared BEFORE the `:id` routes below: both are
  # `/notifications/<segment>`, and Rails matches in declaration order, so
  # "read_all" would otherwise be swallowed as `params[:id] == "read_all"`.
  patch "/notifications/read_all", to: "notifications#read_all", as: :read_all_notifications
  patch "/notifications/:id", to: "notifications#update", as: :notification
  delete "/notifications/:id", to: "notifications#destroy"
end
