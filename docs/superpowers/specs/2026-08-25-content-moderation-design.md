# Content Moderation — Design Spec

**Date:** 2026-08-25
**Status:** Approved (brainstorming complete)
**Scope:** A user flow to flag hujahs (incl. reply "arguments") for review, and a
moderator flow to review flagged content and act on it.

## Problem

A `Flag` model already exists (users can flag a `Hujah` as spam/abusive/irrelevant via
a dialog on the card menu), but there is **no review side**: no moderator identity, no
flag lifecycle, no queue, no way to act on a flag. This spec adds the missing half.

Non-goals: flagging `DebateTurn`s (deferred — would need a polymorphic `Flag`); a
promotion UI for moderators; appeals; audit-log UI; per-flag moderator notifications.

## Decisions (locked)

- Moderator identity: a `role` enum on `User`.
- Flaggable scope: **Hujahs only** — this already covers top-level claims *and* reply
  "arguments", since replies are Hujahs (`parent_id` present).
- Moderator actions: **dismiss**, **remove content**, **warn author**.
- Lifecycle: `status` on `Flag` (each report resolvable) + a `moderation_status` on
  `Hujah` as the single enforcement point.
- Removed content is hidden from **everyone including its author**; the author learns
  via a notification. (Confirmed with product owner.)
- No GitHub PR — work lands on a feature branch, then merges directly to `master`.

## Data model changes

### `users.role` (new)
```ruby
add_column :users, :role, :integer, null: false, default: 0
```
- `enum :role, {member: 0, moderator: 1, admin: 2}, default: :member` (no prefix; the
  methods `moderator?`/`admin?` don't collide with anything today).
- `User#can_moderate?` → `moderator? || admin?`. **This is the only capability gate the
  rest of the app reads** — policies, nav, and views call `can_moderate?`, never `role`
  directly.
- Column-add-with-default is a safe migration on PostgreSQL 11+ (no rewrite), so
  `strong_migrations` will not object.

### `flags` lifecycle columns (new)
```ruby
add_column :flags, :status,      :integer,  null: false, default: 0
add_reference :flags, :resolved_by, foreign_key: {to_table: :users}, null: true
add_column :flags, :resolved_at, :datetime, null: true
add_index :flags, [:user_id, :hujah_id], unique: true, name: "index_flags_on_user_and_hujah"
```
- `enum :status, {pending: 0, dismissed: 1, actioned: 2}, default: :pending`.
- `validates :user_id, uniqueness: {scope: :hujah_id}` — one report per user per hujah.
- `scope :pending, -> { where(status: :pending) }`.
- `Flag#resolve!(by:, as:)` → sets `status`, `resolved_by`, `resolved_at` in one write.
- The unique index is safe here (beta data is minimal; no known duplicate `[user,hujah]`
  rows). If any exist at migration time, dedup them in the migration before the index.

### `hujahs.moderation_status` (new)
```ruby
add_column :hujahs, :moderation_status, :integer, null: false, default: 0
```
- `enum :moderation_status, {active: 0, removed: 1}, default: :active, prefix: :moderation`
  (prefix avoids clashing with `visibility_*` and the debate `status` enum). Gives
  `hujah.moderation_active?` / `hujah.moderation_removed?`.
- **Enforcement (per-record):** `Hujah#visible_to?(viewer)` gains an early gate — if
  `moderation_removed?`, return `viewer&.can_moderate?` (staff-only) *before* any other
  visibility logic.
- **Enforcement (lists):** add `scope :not_removed, -> { where(moderation_status: :active) }`
  and apply it to every list/feed query that does NOT filter per-record through
  `visible_to?`. The implementing agent must locate these: feed/timeline, profile hujah
  lists, `Hujah.trending` (and its 15-min id cache), reply/children rendering, search,
  and any counter that would otherwise count removed content. This is the change with the
  widest blast radius — enumerate call sites before editing.

### `Notification` categories (new — model enum only, no migration)
Add to the existing `enum :category`: `moderation_removed`, `moderation_warning`
(next free integers after `follow_accepted: 13`). Author-facing. Rendered by
`app/views/notifications/_notification_card.html.erb` with an appropriate Lucide icon and
copy; both link to the affected hujah (or its author's context if removed).

## Authorization

Headless `ModerationPolicy` (Pundit resolves the `:moderation` symbol to it):
```ruby
class ModerationPolicy < ApplicationPolicy
  def index?   = user&.can_moderate?
  def dismiss? = user&.can_moderate?
  def remove?  = user&.can_moderate?
  def warn?    = user&.can_moderate?
end
```
Every `ModerationController` action calls `authorize :moderation, :<action>?`, satisfying
the global `after_action :verify_authorized`. Per-record nuance isn't needed — the gate is
purely "is this user staff".

## Routing (main HTML routes — CSRF ON)

```ruby
# Moderator review queue + actions. Staff-only via ModerationPolicy; own-list style
# (no id in the index URL — the queue is global, not user-scoped). These are HTML/Turbo
# write actions, so they live on MAIN routes (CSRF enforced), never under Api::V1.
get    "/moderation",               to: "moderation#index",   as: :moderation
patch  "/moderation/:slug/dismiss", to: "moderation#dismiss", as: :dismiss_moderation
delete "/moderation/:slug/remove",  to: "moderation#remove",  as: :remove_moderation
post   "/moderation/:slug/warn",    to: "moderation#warn",    as: :warn_moderation
```
`:slug` is the flagged hujah's friendly_id. Each carries an explanatory comment per the
routes-file convention.

## Controller

`ModerationController < ApplicationController`:
- `index` — `authorize :moderation, :index?`; loads hujahs that have pending flags,
  eager-loading `:user` and pending `:flags`, ordered by earliest-pending-first (oldest
  reports surface first). Paginated with `pagy(:countless, …)` per house convention.
- `dismiss` — resolve all the hujah's pending flags as `dismissed` (by current_user).
  Content untouched.
- `remove` — set hujah `moderation_removed`, resolve pending flags as `actioned`, create a
  `moderation_removed` notification to the author. Wrapped in a transaction.
- `warn` — create a `moderation_warning` notification to the author, resolve pending flags
  as `actioned`. Content untouched.
- All three action responses: Turbo-Stream that removes the item from the queue (+ updates
  the nav badge count), with an HTML redirect fallback to `/moderation`.

`FlagsController#create` becomes idempotent: `find_or_create_by(user:, hujah:)` then set the
subject, so a second flag by the same user updates the reason instead of raising on the new
unique index. Authorization unchanged (`authorize Flag`).

## Views / UI

- `app/views/moderation/index.html.erb` — the queue: each item a `ui/_card` showing the
  hujah body preview, author (`ui/_avatar`), report count + reason breakdown, timestamps,
  and three action buttons (`ds_button_classes`): **Dismiss** (grey), **Warn** (neutral),
  **Remove** (destructive, `data-turbo-confirm`). Empty state via `ui/_empty_state`.
- `app/views/moderation/_flagged_hujah.html.erb` — one queue item (its own Turbo target
  `dom_id` so an action can stream it away).
- Nav (`app/views/layouts/_navbar` or wherever nav lives): a "Moderation" link with a
  pending-count badge, rendered **only** when `current_user&.can_moderate?`. Count via a
  cached/simple `Flag.pending.distinct.count(:hujah_id)` helper.
- `notifications/_notification_card.html.erb` — branches for the two new categories.
- Verify the flag dialog (`hujahs/_flag_dialog`, embedded via `hujahs/_card_menu`) renders
  on reply hujahs as well as top-level; fix if a reply surface omits the menu.

## Stimulus

Keep JS minimal and purposeful (this is server-rendered Hotwire). The destructive Remove
uses Turbo's `data-turbo-confirm` — no controller needed. Only introduce a Stimulus
controller if a genuine client interaction emerges during build (e.g. an optimistic
queue-item dismiss); if added, it follows Better Stimulus conventions (single
responsibility, values/targets API, no DOM queries by class). The existing `dialog`
controller already backs the flag dialog and is reused as-is.

## Testing

- **Models:** `User` role + `can_moderate?`; `Flag` status/uniqueness/`resolve!`/`pending`;
  `Hujah` `moderation_status`, `visible_to?` staff-only-when-removed, `not_removed` scope.
- **Policy:** `ModerationPolicy` — member denied, moderator/admin allowed, nil user denied.
- **Requests:** `moderation#index` 403 for member / 200 for moderator; `dismiss`/`remove`/
  `warn` each: authz gate, correct flag-status transition, hujah state, notification
  created (remove/warn), Turbo-Stream response. `flags#create` idempotency (second flag by
  same user doesn't 500).
- **Feed/visibility:** a request spec proving a removed hujah disappears from the feed /
  profile / trending for a normal viewer but remains visible to staff.
- **System (js, 1 flow):** a moderator opens `/moderation`, removes a flagged hujah, and it
  leaves the queue; a normal user no longer sees it.

## Quality gates

`bin/ci` must stay green (StandardRB, Brakeman, bundler-audit, full RSpec, Tailwind build).
Any interpolated Tailwind class (e.g. a stance/tone in the queue card) must be safelisted
via `@source inline(...)` — check the built-bundle md5 before/after comment-only edits per
the Tailwind gotchas in CLAUDE.md.

## Execution plan (how this gets built)

Subagent-driven development with **Fable 5 as the orchestrating architect**: Fable owns the
task breakdown and sequences Opus 4.8 subagents that write code under TDD. Ordered slices:

1. **Schema + models** — 3 migrations, `User`/`Flag`/`Hujah`/`Notification` model logic +
   model specs.
2. **Authorization + routes + controller** — `ModerationPolicy`, routes, `ModerationController`,
   `FlagsController` idempotency + request/policy specs.
3. **Enforcement sweep** — `not_removed` across list/feed/trending/search + feed specs.
4. **Views + nav + notifications** — queue UI, nav badge, notification cards, flag-dialog on
   replies + system spec.
5. **Rake task** — `moderation:promote` / `:demote`.

Then three review passes on the diff: **rails-simplifier**, **better-stimulus**,
**rails-security-auditor**; batch fixes; re-run `bin/ci`; merge to `master` and push.
