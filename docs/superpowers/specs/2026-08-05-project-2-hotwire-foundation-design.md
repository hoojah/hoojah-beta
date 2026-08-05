# Project 2 — Slice 1: Hotwire Foundation + Auth + Read/Vote Loop

_Design spec. Date: 2026-08-05. Status: **approved (brainstorming)**, pending specialist review + implementation plan._

## Context

`hoojah-beta` is a Rails **8.1.3.1 / Ruby 3.4.9** app (Project 1 upgrade complete, merged `93a3ff2`).
It currently serves a **React 16 SPA** (`app/javascript/**`) backed by a JSON API (`Api::V1::*`) and a
hand-rolled session `SessionsController`. Project 2 replaces the SPA with **server-rendered Hotwire**
(Turbo + Stimulus) and retires the Webpacker/shakapacker + React + Node toolchain in favour of
**importmap + Propshaft**.

See `docs/superpowers/HANDOVER.md` for full project state and `docs/superpowers/SECURITY-FINDINGS.md`
for the pre-existing vulnerabilities this slice begins to remediate.

Project 2 is delivered in **slices**; this spec is **Slice 1** — the walking skeleton that proves the
full pattern end-to-end (foundation + auth + the core read/vote loop). Slice 2+ (compose form, profile,
notifications, flags) get their own specs.

## Goals (Slice 1)

1. Delete the React SPA + Node/Webpacker/shakapacker build; stand up importmap + Propshaft + Tailwind +
   Turbo + Stimulus.
2. Replace hand-rolled auth with **Devise** (no forced password reset for existing users).
3. Rebuild the two core screens server-side, faithful to today's look: **Hujah index feed** and
   **single Hujah** (vote bars + threaded child responses + response filter).
4. **Voting** works via Turbo Streams, authenticated.
5. Fold in the security fixes that live on this surface (CSRF, votes/hujah-destroy IDOR, login leak,
   mass-assignment, legacy `VotesController`).
6. Establish the test harness (request + JS system specs) and dev tooling (linter, mail preview).

## Non-goals (deferred to Slice 2+)

- Compose/new-Hujah form (incl. "respond to a hujah" flow), user profile page, notifications index,
  flag modal, social-share menu polish.
- Notifications IDOR fix (lives with the notifications UI in Slice 2).
- Removing the JSON API — it **stays** for programmatic/native clients (Project 3), and inherits the
  same auth fixes on shared endpoints.
- Pulling image hosting in-house (ActiveStorage) — Cloudinary stays as a JS-widget URL store.

## Locked decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Slicing | Walking skeleton first (this spec) |
| Security | Fold fixes for this surface into Slice 1 |
| CSS | **Tailwind** (`tailwindcss-rails`), **faithful port** of current look |
| Auth | **Devise** (current line `~> 5.0`) |
| Third-party kept | Cloudinary uploads, Drift chat, social share (as plain links) |
| Icons | **Lucide only** (`lucide-rails`) — no custom SVG partials |
| Voting UI | **Turbo Streams** (server is source of truth) + light Stimulus for button feedback |

## Architecture

### 1. Asset pipeline

**Remove:** `shakapacker` gem + `config/webpacker.yml` + `app/javascript/packs` + `package.json` +
Node engines + `sass-rails`; the `app/javascript` React tree; the shakapacker CVE ignore
(`GHSA-96qw-h329-v5rg`) from `.bundler-audit.yml`.

**Add:** `importmap-rails`, `propshaft`, `tailwindcss-rails`, `turbo-rails`, `stimulus-rails`.

`application.html.erb` swaps `stylesheet_pack_tag`/`javascript_pack_tag` for
`stylesheet_link_tag "tailwind"` + `javascript_importmap_tags`. Carry over the Cloudinary and Drift
`<script>` tags. Tailwind theme tokens encode the agree/neutral/disagree colour system and the
card/vote-bar styles ported from the current SCSS.

### 2. Auth — Devise

**Migration (no forced reset):**
- Rename `password_digest` → `encrypted_password` (both bcrypt `$2a$…`, cost embedded → existing
  passwords validate unchanged).
- Add `reset_password_token` (+ unique index), `reset_password_sent_at`, `remember_created_at`.
- Add a **unique index on `email`** (default `""`) — created `algorithm: :concurrently`
  (enforced by `strong_migrations`).

**Model:** drop `has_secure_password`; add
`devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable`.
(`:confirmable`/`:lockable` deferred — would require confirming the existing user base + extra columns.)
Reconcile validations: Devise owns email + password; keep `username` presence/uniqueness. Move
`photo: User.random_photo` into an `after_create` callback.

**Routes/controllers:** `devise_for :users` with friendly path names preserving **`/login`, `/logout`,
`/signup`** URLs + `/users/password` for reset. Delete `SessionsController`, `UsersController#create`,
and the `/login` `/logout` `/logged_in` routes + `resources :users, only: :create`. Extra signup fields
(`username`, `full_name`) via `configure_permitted_parameters`.

**Ripple:** `current_user` / `user_signed_in?` / `authenticate_user!` now come from Devise → delete the
hand-rolled `ApplicationController` helpers and the app-wide `skip_before_action
:verify_authenticity_token` (**CSRF on**). Sweep `Api::V1::*` + `HujahSerializer` params that call the
old `logged_in?`/`current_user` (still session-backed via Warden). The `/logged_in` endpoint that leaked
`password_digest` is **removed**. Password-reset mail previewed in dev via `letter_opener`.

### 3. Authorization — Pundit (the IDOR fix)

Add `pundit`. Policies (`HujahPolicy`, `VotePolicy`) assert the acting user (from session, **not**
`params[:user_id]`) may perform each action. Enable `after_action :verify_authorized` app-wide so a
missing `authorize` call is a **test failure** — exactly the regression class being fixed.

- `VotePolicy` / votes controller: derive voter from `current_user`; ignore `params[:user_id]` → fixes
  votes IDOR.
- `HujahPolicy#destroy?`: owner-only → fixes hujah-destroy IDOR.
- Delete the legacy top-level `VotesController` + `resources :votes` route.
- User update: drop `:id` from permitted params (mass-assignment fix) — enforced where user update lives.

### 4. Screens

Server-rendered controllers back the HTML UI (the `Api::V1::*` controllers remain for JSON clients):

- **`HujahsController#index`** (`root`) — feed of top-level hujahs as Tailwind cards; logged-out users
  also see the "pinned/intro" block. **Paginated** with `pagy` (`pagy_countless` → Turbo-Stream
  "load more").
- **`HujahsController#show`** — full card, vote bars + percentages, threaded child responses, the
  all/agree/neutral/disagree response **filter**, vote + response counts. Resolved via
  `friendly.find` (see §6).

Body text is rendered server-side with `sanitize` (allowlist the tags the old app emitted) +
`simple_format` + `auto_link` (`rails_autolink`) — the safe replacement for React
`dangerouslySetInnerHTML` + `react-linkify`.

### 5. Voting (Turbo Streams — Approach A)

Each vote button is a Rails form (`button_to`) posting to an authenticated `VotesController#create`.
The controller applies the existing vote semantics — **vote stored as an array** (`vote: [n]`, current =
`.vote.last`), **denormalized counters** on `hujah` (`agree_count`/`neutral_count`/`disagree_count`),
notification on new vote — then responds with a **`turbo_stream`** that re-renders that hujah's vote
partial (bars, %, "voted" state, counts). Server is the source of truth. A small Stimulus controller
gives instant button-press feedback (no client-side counter math — that duplicated logic is deleted).
Unauthenticated vote → redirect to `/login`.

### 6. Slugs — friendly_id (with history)

Replace the abandonware `slug` gem (dead since 2019; produces **non-unique** slugs) with `friendly_id`
`:slugged` + `:history`. Adds the `friendly_id_slugs` table so **old shared/social links survive a body
edit**. `slug_candidates` truncates the parameterized body (first N words + disambiguating token) →
collision-safe, length-controlled. Controller lookups move `find_by_slug` → `friendly.find`. Data
migration backfills slugs for existing hujahs.

### 7. Icons — Lucide only

`lucide-rails` provides one `lucide_icon` helper. Mapping for the current icon set (no custom SVGs):

| App icon | Lucide | | App icon | Lucide |
|---|---|---|---|---|
| agree | `thumbs-up` | | notification | `bell` |
| disagree | `thumbs-down` | | edit | `square-pen` |
| neutral | `minus` | | more_actions | `ellipsis` |
| hujah | `message-circle` | | flag | `flag` |
| votes | `bar-chart-3` | | crown | `crown` |
| home | `house` | | percent | `percent` |
| views | `eye` | | globe | `globe` |
| back | `arrow-left` | | map_pin | `map-pin` |
| share | `share-2` | | trash | `trash-2` |
| announcement | `megaphone` | | | |

### 8. Security hardening (config, no gems)

- CSRF: delete the app-wide `skip_before_action :verify_authenticity_token` (Turbo sends the token).
- `rack-attack` (backed by existing `solid_cache`): throttle `POST /login`, `/signup`, `/users/password`
  per-IP **and** per-email.
- `invisible_captcha`: honeypot on the signup form.
- Headers/CSP via Rails 8 built-ins (`content_security_policy.rb`, `default_headers`, `force_ssl`) —
  **not** the `secure_headers` gem.

## Gem manifest

**Add (default group):** `pundit ~> 2.5`, `rack-attack ~> 6.8`, `invisible_captcha ~> 0.8`,
`pagy ~> 43.6`, `friendly_id ~> 5.7`, `lucide-rails`, `rails_autolink`, `local_time ~> 3.0`,
`devise ~> 5.0`, `importmap-rails`, `propshaft`, `tailwindcss-rails`, `turbo-rails`, `stimulus-rails`.

**Add (dev/test):** `capybara`, `cuprite`, `strong_migrations`, `standard`, `letter_opener` (dev).

**Remove:** `shakapacker`, `sass-rails`, `slug`; the shakapacker CVE ignore in `.bundler-audit.yml`.

**Deferred to Slice 2+:** `prosopite` + `pg_query` (N+1, arrives with the serializer feed),
`shoulda-matchers`, `faker`, `annotaterb`, `devise-pwned_password`, `view_component`, `turbo_power`,
`cloudinary` (ruby) / ActiveStorage, `recaptcha`.

_No gem needed:_ HTML sanitization (Rails built-in), CSRF (delete the skip), security headers (Rails
config). Chose `rails_autolink` over `rinku` (pure Ruby, no native build, speed irrelevant at scale).

## Component boundaries

- `HujahsController` (index/show) — read surface; thin, delegates rendering to partials.
- `VotesController#create` — write + Turbo-Stream response; delegates domain logic to the model.
- `Hujah` model — slug (friendly_id), body sanitization helper, vote-count denormalization,
  `current_user_vote`.
- Policies — `HujahPolicy`, `VotePolicy` (authorization only).
- Partials — `_hujah_card`, `_vote_bars`, `_response_filter`, `_hujah_header` (avatar/handle/share).
- Stimulus — one `vote_controller` (button feedback), one `response_filter_controller` (client-side
  tab filter), plus `local-time`.

Plain ERB partials, not `view_component`, for a faithful port (extract to components later only if a
card is reused across 3+ contexts with logic).

## Testing

- Keep the JSON API request specs green; **update** the characterization specs that currently lock
  insecure behavior (auth changes: `login_as` helper → Warden/Devise `sign_in`).
- **Request specs** for the HTML flows + the Turbo-Stream vote endpoint (assert `turbo_stream` response +
  counter deltas).
- **System specs** (`capybara` + `cuprite`, headless Chrome) for the vote happy-path and the response
  filter — the flagship interactions.
- TDD per task (superpowers). `strong_migrations` gates the Devise migration in dev/test.

## Execution model

After this spec passes specialist review and `writing-plans` produces the implementation plan:
**Fable as architect** (per the `fable-orchestration` skill) decomposes the plan and delegates
token-heavy execution to **Opus subagents** via `subagent-driven-development`, using the
**`better-stimulus`** agent for Stimulus controllers, with a review checkpoint per task and
verification-before-completion throughout. Build/test commands per `HANDOVER.md`
(`mise exec ruby@3.4.9`, `source .mise-build-env.sh`, `RAILS_ENV=test RUBYOPT='-W0' … rspec`,
`bin/rails db:test:prepare`).

## Risks / open items

- **Devise 5.0.x** is newer than prior familiarity — verify API + generator output at install; pin
  `~> 5.0`.
- `lucide-rails` (heyvito) — verify Propshaft/Rails 8.1 compatibility at install; the mapping above is
  provisional pending exact Lucide icon-name availability.
- Devise column rename on a populated table — must run behind `strong_migrations`; verify existing
  logins post-migration.
- Turbo-Stream vote re-render must preserve the array-vote + denormalized-counter semantics exactly
  (characterization specs guard this).
- `rack-cors` currently present for the SPA's cross-origin calls — same-origin Hotwire may not need it,
  but keep for JSON/native clients until Project 3 decides.

## Doc references

| File | What |
|---|---|
| `docs/superpowers/HANDOVER.md` | Project state + build/run quirks |
| `docs/superpowers/SECURITY-FINDINGS.md` | Pre-existing vuln triage |
| `docs/superpowers/UPGRADE-LOG.md` | Project 1 per-hop record |
