# Project 2 — Slice 2: Compose, Profile, Notifications, Flags, Share + Pundit

_Design spec. Date: 2026-08-05. Status: **approved (brainstorming)** + **specialist-reviewed** (security,
Stimulus, simplicity — feedback incorporated, v2). Next: implementation plan._

> **Review incorporation (v2):** Routing → `/u/:username` (kills the greedy-route apparatus); notifications
> → `/notifications` (always current_user, no username-mismatch question). Pundit: exempt Devise
> controllers from `verify_authorized` (else login/signup 500), per-action `skip_authorization`, drop
> `VotePolicy` (`vote?` lives on `HujahPolicy`). Real **M7 = `link` XSS** (add format validation), photo
> host-check is exact-host in the model on both HTML+API. Compose → `after_create_commit` callback (delete
> the duplicated API notification block), not a `compose` method. Dropped prosopite (keep `includes`).
> Added a Stimulus-conventions block (incl. the `close_dialog` Turbo Stream action). Flags "IDOR" reframed
> as hardening (not live-exploitable — AR re-applies the owner FK).

## Context

Slice 1 (merged `ed4c71a`) delivered the Hotwire foundation: importmap+Propshaft+Tailwind, **Devise
5.0.4**, feed + single-hujah + Turbo-Stream voting, and votes/hujah-destroy IDOR fixes via plain
`before_action`. Slice 2 completes the user-facing features and **finishes the authorization story by
adopting Pundit**. React sources for the faithful port: `git show f5b50de:app/javascript/components/<file>`.

## Goals

1. **Compose / respond** — create a hoojah + respond to one (stance-tagged child).
2. **Profile** — view any user's profile + hoojahs; owner can edit (incl. Cloudinary photo).
3. **Notifications** — list + mark-read + delete, scoped to the current user.
4. **Flag** — flag a hoojah (spam/abusive/irrelevant).
5. **Social share** — share menu (intent links + Web Share API).
6. **Pundit** — adopt it; migrate Slice 1's IDOR checks to policies; close the notifications IDOR/leak +
   flags hardening on **both** the HTML and `Api::V1` surfaces; fix the `link` XSS (M7).

## Non-goals (deferred)

Vote array→scalar collapse; prosopite/serializer N+1 refactor (the JSON serializers have known N+1s —
own slice); ActionCable notification push; `require_master_key`; `rack-cors` origin tightening;
Project 3 (Hotwire Native).

## Locked decisions

| Decision | Choice |
|---|---|
| Slice shape | One slice, all 5 screens |
| Authorization | **Adopt Pundit** (migrate Slice 1 `before_action` checks into policies) |
| Profile | View **+ edit** (Cloudinary photo + URL host validation) |
| Vote array→scalar | Kept separate (later slice) |
| Modals | Native `<dialog>` + a shared `dialog` Stimulus controller |
| **Profile URLs** | **`/u/:username`** (plain prefix — no greedy route, cleanest for Project 3 native/deep-links) |
| Notifications URL | **`/notifications`** (HTML; always current_user — no username in the path) |
| Compose body | Raw text (drop React's `\n`→`<br>`); rendered via the existing `format_body` |
| N+1 | `includes` only; **prosopite deferred** |

## Architecture

### 1. Pundit (authorization spine)

Add `pundit`. `ApplicationController` includes `Pundit::Authorization`; `rescue_from
Pundit::NotAuthorizedError` → HTML redirect+flash / JSON `head :forbidden`. Enable app-wide
authorization enforcement **exempting Devise** (its controllers inherit `ApplicationController` and would
otherwise 500 on every login/signup/logout/password action — the CRITICAL review finding):

```ruby
after_action :verify_authorized, unless: :devise_controller?
```

**Per-action `skip_authorization` / `authorize` (never a blanket per-controller skip — that would
silently exempt `destroy` and reopen the Slice 1 IDOR):**

| Controller · action | Wiring |
|---|---|
| `HujahsController#index/#show/#new` (public/authed reads + form) | `skip_authorization` inline |
| `HujahsController#create` | `authorize Hujah` (→ `HujahPolicy#create?` = `user.present?`) |
| `HujahsController#destroy` + `Api::V1::HujahsController#destroy` | `authorize @hujah` (`#destroy?` = owner) — replaces Slice 1 `require_owner!` |
| `VotesController#create` + `Api::V1::VotesController#create` | `authorize @hujah, :vote?` (→ **`HujahPolicy#vote?`** = `user.present?`) — replaces Slice 1 `before_action` |
| `NotificationsController#index` | `policy_scope(Notification)` (current_user's own) |
| `NotificationsController#update/#destroy` + `Api::V1` twins | `authorize @notification` (owner) |
| `UsersController#update` + `Api::V1::UsersController#update` | `authorize @user` (`#update?` = self) |
| `FlagsController#create` + `Api::V1::FlagsController#create` | `authorize Flag` (`#create?` = `user.present?`) |

**Policies (`app/policies/`, 4 total):** `HujahPolicy` (`destroy?` owner, `create?`/`vote?` =
`user.present?`), `NotificationPolicy` + `Scope` (`update?`/`destroy?` owner; `Scope#resolve` →
`user ? scope.where(user:) : scope.none`), `UserPolicy` (`update?` self), `FlagPolicy` (`create?` =
`user.present?`). **No `VotePolicy`** (Pundit infers policy from the record's class → `@hujah` resolves
`HujahPolicy`). Keep Vote/Flag policies trivial — `user.present?`, no roles.

**Defense-in-depth (medium findings):** the `Api::V1::{Notifications,Flags}Controller` +
`Api::V1::UsersController#update` also get explicit `before_action :authenticate_user!` (today
`Api::V1::FlagsController#create` 500s on a nil `current_user`) so "no user" is a clean 401, not a
policy nil-deref. This task ships **first**, behind a full-suite gate, with request specs asserting
`/login /signup /logout /password/new` + every controller action authorize/skip exactly once.

### 2. Compose / respond

- **Routes:** `GET /hoojah/new` → `HujahsController#new`; `GET /hoojah/:slug/respond` → `#new` w/ `@parent`;
  `POST /hoojah` → `#create`. RESTful (not the API's `hoojah/create` style).
- **`#new`:** compose form; for a response, the parent card + a stance picker (agree/neutral/disagree,
  defaulting to the current user's vote on the parent). The child hoojah stores that stance in its `vote`
  integer column.
- **`#create`:** `current_user.hujahs.create(body:, parent_id:, vote:)` (body stored raw; `parent_id`
  must be validated to exist — guard the nil-parent deref). The `new_hoojah_response` notification is a
  **model callback**, not controller code:
  ```ruby
  # app/models/hujah.rb
  after_create_commit :notify_parent_owner, if: :has_parent?
  ```
  and **delete the duplicated inline notification block** in `Api::V1::HujahsController#create` (both
  paths now notify via the callback — DRY, and parallels `cast_vote`). Redirect (Turbo) to the new hoojah.
- Fix the pre-existing `Hujah#has_children?` bug (`children != 0` is always true) since compose/profile
  show child counts.

### 3. Profile (view + edit) — `/u/:username`

- **Route:** `GET /u/:username` → `UsersController#show` (HTML). Renders avatar, full_name, @username,
  headline, location, link, `hujah_count`/`vote_count`, and the user's hoojahs.
- **`link` is rendered as text or a validated `<a href>`** — if clickable, the **M7 fix is a blocking
  dependency**: `validates :link, format: { with: %r{\Ahttps?://}i }, allow_blank: true` on `User`
  (model-level, so the API path inherits it). This is the actual deferred finding M7 (`link` stored-XSS),
  which Slice 1 left open.
- **Edit (owner only, `UserPolicy#update?` = self):** `GET /u/:username/edit` → edit form in a native
  `<dialog>`; `PATCH /u/:username` → `#update`. Fields: full_name, username, location, link, headline,
  photo. (Email stays API-only, matching the React edit form which omits it.)
- **Username validation at the MODEL** (not just the controller) — a second edit path already exists via
  Devise's account-update (`/edit` → `Users::RegistrationsController`, which permits `username`/`full_name`),
  so controller-only rules are bypassable:
  ```ruby
  RESERVED_USERNAMES = %w[login signup logout password edit cancel new hoojah hoojahs u users notifications rails api admin].freeze
  validates :username, format: { with: /\A[a-zA-Z0-9_]+\z/ }, exclusion: { in: RESERVED_USERNAMES }
  ```
  (Belt-and-suspenders even though `/u/` namespacing already prevents route shadowing.)
- **Photo upload:** Cloudinary JS widget (`window.cloudinary`) wrapped in `cloudinary_upload_controller`
  → writes `secure_url` to a hidden field. **Server host-validation in the model** (both HTML + API
  inherit it), exact-host (not substring — defeats `res.cloudinary.com.evil.com` and userinfo `@evil.com`
  tricks):
  ```ruby
  validate :photo_from_cloudinary
  def photo_from_cloudinary
    return if photo.blank?
    uri = URI.parse(photo)
    ok = uri.scheme == "https" && uri.host == "res.cloudinary.com" && uri.path.start_with?("/hoojah/")
    errors.add(:photo, "must be a Hoojah Cloudinary URL") unless ok
  rescue URI::InvalidURIError
    errors.add(:photo, "is not a valid URL")
  end
  ```
  (Path prefix `/hoojah/` restricts to the app's own cloud, not just any Cloudinary customer.)
- `:id` already excluded from permit list (Slice 1).

### 4. Notifications (+ IDOR/leak fix on HTML and API) — `/notifications`

- **HTML route:** `GET /notifications` → `NotificationsController#index`, `policy_scope(Notification)` →
  **always the current_user's own** (no username in the URL → the read-leak + mismatch questions vanish).
- **Mark read + open:** `PATCH /notifications/:id` → `NotificationsController#update` (RESTful, not a
  bespoke `#read_and_go`): sets `read: true`, `authorize @notification` (owner), redirects to the hoojah.
- **Delete:** `DELETE /notifications/:id` → Turbo-Stream removes the card; `authorize @notification`.
- **`Api::V1::NotificationsController`** (native clients) gets the same fixes: `#index` via
  `policy_scope` (was `@user.notifications` for *any* `params[:username]` — a read leak), `#update`/
  `#destroy` `authorize` the owner (was `Notification.find(params[:id])`, no check). **Delete the dead
  `find_user`/`@user` lookup** so a future edit can't revert to `@user.notifications`. **Rewrite
  `spec/requests/api/v1/notifications_spec.rb`** to assert the secure behavior.
- Card categories (faithful port): `announcement` / `new_hoojah_response` / `new_vote`; read/unread
  left-border; Lucide icons; trash to delete.
- Add `after_create_commit`-safe: confirm the `subject_user` association exists before eager-loading —
  the `Notification` model has a `subject_user_id` column but **no `belongs_to :subject_user`**; add
  `belongs_to :subject_user, class_name: "User", optional: true`.
- `User#unread_notifications_count` → `notifications.unread.count` (use the existing `unread` scope).

### 5. Flag (hardening + IDOR-shape fix on HTML and API) — `POST /hoojah/:slug/flags`

- **Route:** `POST /hoojah/:slug/flags` → `FlagsController#create`. Reasons spam/abusive/irrelevant in a
  native `<dialog>` on the hoojah show page. **Actor from `current_user`; `:user_id` dropped from params.**
  (Note: not a *live* IDOR today — `current_user.flags.create` already forces the owner FK via
  ActiveRecord; this is hardening against a future refactor + defense-in-depth.) Responds with a
  Turbo-Stream that closes the dialog (see §8's `close_dialog` action) + a confirmation.
- **`Api::V1::FlagsController#create`** gets the same param fix **plus** `before_action
  :authenticate_user!` (it currently 500s on a nil `current_user`).

### 6. Social share

Replace `react-share` with a share menu on the hoojah header: **plain server-rendered `<a href>` intent
links** (WhatsApp `wa.me`, X/Twitter intent, Telegram, Reddit, Facebook sharer, `mailto:`) built from the
hoojah's absolute URL + body — these work with **zero JS**. Plus a **Web Share** button, `hidden` by
default, revealed by `share_controller` only when `"share" in navigator`.

### 7. Routing

Profiles under `/u/:username` (+ `/u/:username/edit`), notifications at `/notifications`, flags at
`/hoojah/:slug/flags`, compose at `/hoojah/new` + `/hoojah/:slug/respond` + `POST /hoojah`. No greedy
top-level segment, no reserved-word regex, no shadowing risk. The `Api::V1` routes (incl.
`/:username/notifications`) stay unchanged for native clients.

### 8. Stimulus conventions (Slice 2)

Follows Slice 1's conventions (file `snake_case_controller.js` ↔ `data-controller="kebab-case"`, actions
via `data-action`, no manual listeners). Three new controllers:

**`dialog_controller`** (shared by profile-edit + flag — same *behavior*, different content):
- Wrapper element holds trigger + `<dialog>`; `static targets = ["dialog"]`. `open()` →
  `this.dialogTarget.showModal()` (**not** `show()` — needed for backdrop/top-layer/Esc/`inert`).
- Backdrop-close is **not** native: `data-action="click->dialog#backdropClose"` on the dialog,
  `backdropClose(e){ if (e.target === this.dialogTarget) this.dialogTarget.close() }`.
- Focus restore: capture `document.activeElement` in `open()`; `data-action="close->dialog#restoreFocus"`
  on the dialog refocuses it (fires for Esc, backdrop, or programmatic close).
- `teardown(){ if (this.dialogTarget.open) this.dialogTarget.close() }`, invoked by a one-time
  `turbo:before-cache` loop added to `application.js`:
  `document.addEventListener("turbo:before-cache", () => application.controllers.forEach(c => c.teardown?.()))`.
- Partials set `aria-labelledby` on each `<dialog>` (`dialog-title-flag`, `dialog-title-profile-edit`).
- **Remote close after a server action:** register once in `application.js`
  `Turbo.StreamActions.close_dialog = function(){ this.targetElements.forEach(el => el.close()) }`; the
  flag-create and profile-update Turbo-Stream responses emit
  `<turbo-stream action="close_dialog" target="<dom_id>">` (ids `dom_id(@hujah, :flag_dialog)`,
  `dom_id(@user, :edit_dialog)`).

**`cloudinary_upload_controller`:** `connect()` → `this.widget = window.cloudinary.createUploadWidget(
opts, (err, res) => this.onUpload(err, res))` (arrow fn — never pass a bare method ref, `this` would be
wrong); guard `if (!window.cloudinary)` (CSP/adblock/offline) → disable button. `open()` →
`this.widget.open()`. On success: `this.hiddenTarget.value = res.info.secure_url;
this.hiddenTarget.dispatchEvent(new Event("input", { bubbles: true }))`. The hidden field **is** the
state (no Values). `window.cloudinary` is a global (loaded via the layout `<script>`, Slice 1 CSP) —
**not** an importmap module.

**`share_controller`:** feature-detect in `connect()` (`"share" in navigator` → unhide the native
button). `share(e)` → `navigator.share({title,text,url})` from `static values = {title,text,url}`;
swallow `AbortError` (user-cancel) — rethrow others. Fallback link menu is always server-rendered.

_(No shared `ApplicationController` JS base this slice — each controller does local guarding; revisit if
a 4th controller wants shared error handling.)_

## Gem manifest

**Add:** `pundit ~> 2.5` (only). No prosopite/pg_query (deferred). `<dialog>`/share/Cloudinary add no
gems.

## Component boundaries

- Thin HTML controllers: `HujahsController` (+new/create/destroy), `UsersController` (show/edit/update),
  `NotificationsController` (index/update/destroy), `FlagsController` (create) — delegate to models +
  policies.
- Model: `Hujah` gains `after_create_commit :notify_parent_owner`; `User` gains `link`/`photo`/`username`
  validations + `unread_notifications_count` cleanup; `Notification` gains `belongs_to :subject_user`.
- Policies: `app/policies/{hujah,notification,user,flag}_policy.rb` (+ `NotificationPolicy::Scope`).
- Partials: `_compose_form`, `_parent_card`, `_stance_picker`, `_profile_header`, `_profile_edit`,
  `_notification_card`, `_flag_dialog`, `_share_menu`, `_user_hujah`.
- Stimulus: `dialog`, `cloudinary_upload`, `share` (+ Slice 1's `response_filter`) + the
  `turbo:before-cache` teardown loop + the `close_dialog` Turbo Stream action in `application.js`.
- `Api::V1::*` JSON controllers/serializers stay for native clients; inherit the IDOR/validation fixes.

## Testing

- **Rewrite** `spec/requests/api/v1/notifications_spec.rb` (index scoped to current_user; update/destroy
  owner-only, unauth→401). Extend `flags_spec.rb` (`:user_id` dropped, unauth→401).
- **Pundit rollout gate:** a request-spec matrix asserting every action authorizes/skips exactly once,
  and `/login /signup /logout /password/new` + Devise account-update still work.
- **Request specs:** compose (new/create + response stance + notification via callback + missing-parent
  guard), profile (show; owner edit; **`link` non-http rejected**; **photo non-Cloudinary-host rejected**,
  incl. the `res.cloudinary.com.evil.com`/`@evil.com` bypass strings), notifications (list/read-redirect/
  delete Turbo-Stream; another user's notification 403), flag (Turbo-Stream + `:user_id` ignored), share
  menu present with no-JS links.
- **System specs (cuprite):** compose→redirect; profile-edit dialog opens/saves/closes (incl. the
  Cloudinary widget iframe opening — `frame-src`); flag dialog; notification delete removes the card;
  Web Share fallback menu.
- **rack-attack:** extend throttles to `POST /hoojah` (compose) and `POST /hoojah/:slug/flags`
  (spam/mass-flag DoS); add a throttle spec.
- Eager-load `includes` on profile (`user.hujahs.includes(:user)`) + notifications
  (`.includes(:hujah, :subject_user)`). TDD per task. Full suite green; brakeman 0; bundler-audit clean;
  StandardRB clean.

## Execution model

Same as Slice 1: this reviewed spec → `writing-plans` → subagent-driven-development (Opus executors +
per-phase independent review gates; Fable-style advisor for ambiguous judgment). Build/test commands per
`HANDOVER.md`.

## Risks / open items

- **Pundit rollout is all-or-nothing** — Devise exemption + every controller wired in the first task,
  full-suite gate. Request specs assert auth flows survive.
- **`link`/`photo` validations** must live on the model (both HTML + API edit paths). Exact-host photo
  parsing; `URI::InvalidURIError` rescued.
- **Second username-edit path** via Devise account-update — model validation covers it; decide separately
  whether to drop `username`/`full_name` from `configure_permitted_parameters` (recommended: keep, now
  that the model validates).
- **`subject_user` association** must be added before eager-loading/serializing notifications.
- Cloudinary widget iframe under CSP (`frame-src widget.cloudinary.com` from Slice 1) — assert it opens
  in a system test.

## Deferred to later slices

Vote array→scalar + counter collapse; serializer N+1 refactor + prosopite; ActionCable notification push;
`require_master_key`; `rack-cors` origin tightening; Project 3 (Hotwire Native).

## Doc references

| File | What |
|---|---|
| `docs/superpowers/specs/2026-08-05-project-2-hotwire-foundation-design.md` | Slice 1 design |
| `docs/superpowers/plans/2026-08-05-project-2-hotwire-foundation.md` | Slice 1 plan |
| `docs/superpowers/HANDOVER.md` | Project state + build quirks |
| `docs/superpowers/SECURITY-FINDINGS.md` | Pre-existing vuln triage (M7 = `link` XSS, closed here) |
