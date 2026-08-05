# Project 2 — Slice 2: Compose, Profile, Notifications, Flags, Share + Pundit

_Design spec. Date: 2026-08-05. Status: **approved (brainstorming)**, pending specialist review + implementation plan._

## Context

Slice 1 (merged to `master` `ed4c71a`) delivered the Hotwire foundation: importmap+Propshaft+Tailwind,
**Devise 5.0.4** auth, the feed + single-hujah + Turbo-Stream voting, and the votes/hujah-destroy IDOR
fixes via plain `before_action`. Slice 2 completes the user-facing features and **finishes the
authorization story by adopting Pundit**.

Read `docs/superpowers/specs/2026-08-05-project-2-hotwire-foundation-design.md` (Slice 1 design) and
`docs/superpowers/HANDOVER.md` first. React sources for the faithful port live in git history at
`git show f5b50de:app/javascript/components/<file>`.

## Goals (Slice 2)

1. **Compose / respond** — create a new hoojah and respond to one (stance-tagged child).
2. **Profile** — view any user's profile + their hoojahs; owner can edit (incl. Cloudinary photo).
3. **Notifications** — list + mark-read + delete, scoped to the current user.
4. **Flag** — flag a hoojah (spam/abusive/irrelevant).
5. **Social share** — share menu (intent links + Web Share API).
6. **Pundit** — adopt it; migrate Slice 1's IDOR `before_action`s to policies; close the notifications +
   flags IDORs on **both** the HTML and `Api::V1` surfaces.

## Non-goals (deferred)

- Vote model array→scalar + counter collapse (its own later slice).
- `require_master_key` / `rack-cors` origin tightening (Project 3 concerns).
- Real-time notification push (ActionCable) — the index is request/Turbo-driven for now.
- Project 3 (Hotwire Native).

## Locked decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Slice shape | One slice, all 5 screens |
| Authorization | **Adopt Pundit now** (migrate Slice 1 `before_action` checks into policies) |
| Profile | View **+ edit** (Cloudinary photo upload + URL host validation) |
| Vote array→scalar | **Kept separate** (later slice) |
| Modals (edit/flag) | Native `<dialog>` + a small Stimulus controller |
| `/:username` route | Greedy, declared **last**, constrained to exclude reserved paths |
| Compose body | Stored as **raw text** (drop React's `\n`→`<br>` hack); rendered via `format_body` |

## Architecture

### 1. Pundit (authorization spine)

Add `pundit`. `ApplicationController` includes `Pundit::Authorization`, `rescue_from
Pundit::NotAuthorizedError` → 403 (HTML: redirect + flash; JSON: `head :forbidden`). Enable
`after_action :verify_authorized` app-wide **and wire every existing controller** — the Slice 1 security
review's footgun (an app-wide verify that 500s untouched controllers) is closed by doing the rollout
deliberately:

| Controller | Wiring |
|---|---|
| `HujahsController` index/show, feed | `skip_authorization` / public reads (`verify_authorized` exempt for index/show) or `authorize` where owned |
| `HujahsController#create` | `authorize Hujah` (authed) |
| `VotesController#create` (HTML + `Api::V1`) | `authorize @hujah, :vote?` (authed) — replaces Slice 1 `before_action` |
| `HujahsController#destroy` / `Api::V1::HujahsController#destroy` | `authorize @hujah` (owner) — replaces Slice 1 `require_owner!` |
| `NotificationsController` (HTML + `Api::V1`) | `policy_scope` on index; `authorize @notification` on update/destroy (owner) |
| `UsersController#update` (HTML + `Api::V1`) | `authorize @user` (self) |
| `FlagsController#create` (HTML + `Api::V1`) | `authorize Flag` (authed) |

Policies (plain Ruby, `app/policies/*`): `HujahPolicy`, `VotePolicy`, `NotificationPolicy` (+ `Scope`),
`UserPolicy`, `FlagPolicy`. Each rule guarded by a request spec asserting the secure behavior.

### 2. Compose / respond

- **Routes:** `GET /hoojah/new` → `HujahsController#new` (top-level); `GET /hoojah/:slug/respond` →
  `#new` with `@parent` (response); `POST /hoojah` → `#create`.
- **`#new`**: renders the compose form. For a response, shows the parent card + a stance picker
  (agree/neutral/disagree) defaulting to the current user's existing vote on the parent; the child
  hoojah stores that stance in its `vote` column (an integer). Entry points: the feed/show "Add hoojah"
  buttons (Slice 1's `ButtonAddHujah`) link to `/hoojah/:slug/respond`.
- **`#create`**: `current_user.hujahs.create(body:, parent_id:, vote:)`; for a reply, create a
  `new_hoojah_response` Notification to the parent's owner (move this into a rich-model method
  `Hujah.compose(author:, body:, parent:, stance:)` so the controller stays thin, mirroring
  `cast_vote`). Body stored raw; rendered with `format_body`. Redirect (Turbo) to the new hoojah's show.
- **Stimulus**: the stance picker is a radio group styled with Tailwind + a tiny controller only if
  needed (prefer CSS `:checked`); a `char/empty` disable on the submit button via Turbo/CSS.

### 3. Profile (view + edit)

- **Route:** `GET /:username` → `UsersController#show` (HTML) — declared LAST, constrained
  `:username` to exclude reserved words (see §7). Renders avatar, full_name, @username, headline,
  location, link, `hujah_count`/`vote_count`, and the user's hoojahs (reuse a small card partial).
- **Edit (owner only, Pundit `UserPolicy#update?` = self):** `GET /:username/edit` → an edit form in a
  native `<dialog>`; `PATCH /:username` → `#update`. Fields: full_name, username, location, link,
  headline, photo.
- **Photo upload:** keep the Cloudinary JS widget (`cloudinary.openUploadWidget({cloud_name:'hoojah',
  upload_preset:'user_photo'})`), wrapped in a `cloudinary_upload_controller` (Stimulus) that writes the
  returned `secure_url` into a hidden field + updates the preview. **Server validates** the submitted
  photo URL host is `res.cloudinary.com` (closes deferred finding M7) — reject otherwise.
- Strong params already exclude `:id` (Slice 1). `username` change keeps the uniqueness validation.

### 4. Notifications (+ IDOR fix on HTML and API)

- **Route:** `GET /:username/notifications` → `NotificationsController#index` (HTML). **Scoped to
  `current_user`** via `policy_scope` — currently `Api::V1::NotificationsController#index` returns *any*
  username's notifications (a read leak); the HTML controller ignores `:username` and lists
  `current_user.notifications` (verify the URL username matches current_user, else redirect).
- **Mark read + open:** clicking a notification `PATCH`es `read: true` then redirects to the hoojah
  (a single server action `#read_and_go`, or a link that hits `#update` with a redirect). Owner-only.
- **Delete:** `DELETE` → Turbo-Stream removes the card; owner-only.
- **`Api::V1::NotificationsController`** gets the same fixes: `#index` scoped to `current_user`,
  `#update`/`#destroy` authorize the notification's owner (was `Notification.find(params[:id])` with no
  check). **Rewrite `spec/requests/api/v1/notifications_spec.rb`** to assert the secure behavior.
- Notification card categories (faithful port): `announcement`, `new_hoojah_response`, `new_vote`,
  with read/unread left-border styling, Lucide icons (`megaphone`/`message-circle`/`bar-chart-3`), trash
  to delete.

### 5. Flag (+ IDOR fix on HTML and API)

- **Route:** `POST /hoojah/:slug/flags` → `FlagsController#create` (HTML). Flag reasons
  spam/abusive/irrelevant in a native `<dialog>` on the hoojah show page. **Actor derived from
  `current_user`; `:user_id` dropped from params** (was permitted → IDOR). Responds with a Turbo-Stream
  that closes the dialog + shows a confirmation.
- **`Api::V1::FlagsController#create`** gets the same fix (drop `:user_id`, derive from `current_user`,
  require auth). Extend the flags request spec to assert it.

### 6. Social share

Replace `react-share` with a share menu on the hoojah header: plain intent links (WhatsApp `wa.me`,
Twitter/X intent, Telegram, Reddit, Facebook sharer, `mailto:`) built from the hoojah's absolute URL +
body, plus a **Web Share API** button via a `share_controller` (Stimulus) calling `navigator.share(...)`
with a graceful fallback to the link menu when unsupported.

### 7. Routing (greedy `/:username`)

`/:username` and `/:username/notifications` are greedy and MUST be declared **after** all fixed routes
(root, `/hoojah/*`, `/hoojah/:slug/respond`, `/hoojah/:slug/flags`, devise `/login /signup /logout
/password`). Constrain with `constraints: { username: /(?!login|signup|logout|password|hoojah|users|
rails)[a-zA-Z0-9_]+/ }` (or a reserved-words check in the controller) so real routes are never captured.

### 8. Modals — native `<dialog>` + Stimulus

One `dialog_controller` (Stimulus): `open()` → `el.showModal()`, `close()` → `el.close()`, closes on
backdrop click + `Esc` (native). Used by profile edit and flag. No Bootstrap-JS, no extra deps;
accessible by default.

### 9. N+1 (prosopite)

Add `prosopite` + `pg_query` (dev/test). Wrap request/system specs in `Prosopite.scan`/`finish` (raise on
N+1). Eager-load the obvious spots: profile (`user.hujahs.includes(:user)`), notifications
(`.includes(:hujah, :subject_user_user)` as modeled), and confirm the feed/show include chains from
Slice 1 hold.

## Gem manifest

**Add (default):** `pundit ~> 2.5`. **Add (dev/test):** `prosopite`, `pg_query`.
No other new gems — `<dialog>`, share, and Cloudinary are Stimulus + the existing Cloudinary widget
script (already in the layout). Cloudinary stays a JS-widget URL store (no ruby gem / ActiveStorage).

## Component boundaries

- Controllers (HTML): `HujahsController` (+ `new`/`create`/`destroy`), `UsersController`
  (`show`/`edit`/`update`), `NotificationsController` (`index`/`update`/`destroy`), `FlagsController`
  (`create`) — all thin, delegating to models + policies.
- Rich-model methods: `Hujah.compose(author:, body:, parent:, stance:)` (create + response notification);
  keep `cast_vote` from Slice 1.
- Policies: `app/policies/{hujah,vote,notification,user,flag}_policy.rb`.
- Partials: `_compose_form`, `_parent_card`, `_stance_picker`, `_profile_header`, `_profile_edit`
  (dialog), `_notification_card`, `_flag_dialog`, `_share_menu`, `_user_hujah` (small card).
- Stimulus: `dialog_controller`, `cloudinary_upload_controller`, `share_controller` (+ Slice 1's
  `response_filter_controller`). All follow Slice 1's Stimulus conventions (naming, `data-action`, no
  manual listeners, Values/Classes APIs, a11y).
- The `Api::V1::*` JSON controllers + serializers stay for native clients; they inherit the IDOR fixes.

## Testing

- **Rewrite** `spec/requests/api/v1/notifications_spec.rb` to assert IDOR closed (index scoped to
  current_user; update/destroy owner-only). Extend `flags_spec.rb` to assert the `:user_id` fix.
- **Request specs** for compose (new/create + response w/ stance + notification), profile (show + owner
  edit + Cloudinary host validation reject), notifications (list/read/delete Turbo-Stream), flag
  (Turbo-Stream), share menu presence, and every Pundit rule (owner vs non-owner vs unauth).
- **System specs** (cuprite): compose→redirect, profile edit dialog + save, flag dialog, notification
  delete removes the card, Web Share fallback menu opens.
- **prosopite** raises on N+1 during request/system specs.
- TDD per task. Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Execution model

Same as Slice 1: spec → **specialist review (rails-security-auditor, better-stimulus, rails-simplifier)**
→ `writing-plans` → subagent-driven-development with Opus executors + per-phase independent review gates;
Fable-style advisor routing reserved for ambiguous judgment. Build/test commands per `HANDOVER.md`
(`mise exec ruby@3.4.9`, `source .mise-build-env.sh`, `RAILS_ENV=test RUBYOPT='-W0' … rspec`,
`bin/rails db:test:prepare`).

## Risks / open items

- **Pundit `verify_authorized` rollout** must touch every controller in one pass or the app 500s — the
  plan sequences this as the first Pundit task with a full-suite gate.
- **Greedy `/:username`** can shadow real routes — the constraint + a test asserting `/login` etc. still
  resolve to Devise are required.
- **Cloudinary widget under CSP** — the Slice 1 CSP already allows `widget.cloudinary.com` +
  `api.cloudinary.com`; verify the upload widget actually opens (frame-src) during a system test.
- **Migrating Slice 1 before_action → Pundit** must not regress the votes/destroy IDOR specs — they stay
  green through the migration.
- Notification `subject_user` association: confirm the model/column name before eager-loading.

## Deferred to later slices

Vote array→scalar + counter collapse; ActionCable notification push; `require_master_key`; `rack-cors`
origin tightening; Project 3 (Hotwire Native).

## Doc references

| File | What |
|---|---|
| `docs/superpowers/specs/2026-08-05-project-2-hotwire-foundation-design.md` | Slice 1 design |
| `docs/superpowers/plans/2026-08-05-project-2-hotwire-foundation.md` | Slice 1 plan |
| `docs/superpowers/HANDOVER.md` | Project state + build quirks |
| `docs/superpowers/SECURITY-FINDINGS.md` | Pre-existing vuln triage |
