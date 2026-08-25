# Content Moderation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the review half of flagging — a `role` on User, a lifecycle on Flag, a `moderation_status` on Hujah as the single enforcement point, a staff-only `/moderation` queue with dismiss/remove/warn actions, author notifications, and a `not_removed` sweep across every list surface.

**Architecture:** Three additive columns (all safe on PG 11+), one headless Pundit policy (`ModerationPolicy`), one hand-written-route controller (`ModerationController`) on MAIN routes (CSRF on), and enforcement at exactly two seams: `Hujah#visible_to?` (per-record, gains a staff-only early gate) and a new `Hujah.not_removed` scope (applied at every list/count site that does not filter per-record). Design spec: `docs/superpowers/specs/2026-08-25-content-moderation-design.md` — its decisions are locked; do not re-litigate them.

**Tech Stack:** Rails 8.1, Hotwire (Turbo Streams, no new Stimulus), Devise, Pundit, pagy `:countless`, strong_migrations, RSpec + FactoryBot, Tailwind v4.

---

## Ground rules (from CLAUDE.md — violations fail review)

- Every non-Devise controller action calls `authorize` or `skip_authorization` exactly once.
- HTML write actions live on MAIN routes, never under `Api::V1`.
- Migrations must pass strong_migrations (no bare `execute` without `safety_assured` + justification; concurrent index outside a DDL transaction).
- StandardRB clean (`bundle exec standardrb`). `bin/**`, `db/migrate/**`, `db/schema.rb` are excluded.
- `ui/_card` is a **layout** partial (`render layout: "ui/card" do … end`).
- In ERB, never name a concrete Tailwind class in a comment/prose — the scanner compiles it into a real rule. Ruby `#` comments are safe.
- No new `@source inline(...)` entries are needed **if** views stick to existing helpers/tones (they do in this plan). Any *new* interpolated class family would need one.
- Commit subjects: plain imperative, **no Claude/Anthropic branding**. This is not roadmap-slice work, so do NOT use the `Slice N Task X.Y:` prefix; use e.g. `Moderation: add users.role enum and can_moderate?`.
- Test runs: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec <path>`. One full suite at a time (shared Postgres test DB).
- All work on feature branch `content-moderation` off `master`; merged directly to `master` at the end (no PR).

## Slice ordering / parallelism

1. **Slice 1 (schema + models)** — serial, first. Everything depends on it.
2. **Slice 2 (authz + routes + controller + queue views)** and **Slice 3 (enforcement sweep)** — may run **in parallel** after Slice 1 (disjoint files: Slice 2 touches policies/routes/`moderation_*`/`flags_controller`; Slice 3 touches `hujah.rb` scopes, feed/profile/tags/search/API-index/analytics call sites). If parallel, each agent runs only its own targeted specs; the full suite runs once both land.
3. **Slice 4 (nav + notifications + system spec)** — after Slices 2 AND 3.
4. **Slice 5 (rake task)** — independent; any time after Slice 1.
5. Finish: `bin/ci`, review passes (rails-simplifier, better-stimulus, rails-security-auditor), batched fixes, merge.

Note one deliberate deviation from the spec's slice list: the queue **views** (`moderation/index`, `_flagged_hujah`, the three turbo_stream templates) are built in Slice 2, not Slice 4 — Rails request specs render views, so `moderation#index` specs cannot pass without them. Slice 4 keeps the navbar entry, notification cards, reply-flag verification, and the system spec.

## File Structure

**Create**
- `db/migrate/<ts>_add_role_to_users.rb` — `users.role` integer, default 0.
- `db/migrate/<ts>_add_moderation_status_to_hujahs.rb` — `hujahs.moderation_status` integer, default 0.
- `db/migrate/<ts>_add_lifecycle_to_flags.rb` — `flags.status`, `flags.resolved_at`, `flags.resolved_by_id` (+ FK).
- `db/migrate/<ts>_add_unique_index_to_flags.rb` — dedup then unique `[user_id, hujah_id]` index, concurrently.
- `app/policies/moderation_policy.rb` — headless staff gate (`index?/dismiss?/remove?/warn?`).
- `app/controllers/moderation_controller.rb` — queue + the three actions.
- `app/views/moderation/index.html.erb` — the queue page.
- `app/views/moderation/_flagged_hujah.html.erb` — one queue item (own `dom_id` Turbo target).
- `app/views/moderation/dismiss.turbo_stream.erb`, `remove.turbo_stream.erb`, `warn.turbo_stream.erb` — remove item + refresh counts.
- `app/helpers/moderation_helper.rb` — `pending_moderation_count`.
- `lib/tasks/moderation.rake` — `moderation:promote[username]` / `moderation:demote[username]`.
- Specs: `spec/policies/moderation_policy_spec.rb`, `spec/requests/moderation_spec.rb`, `spec/requests/moderation_visibility_spec.rb`, `spec/system/moderation_spec.rb`, `spec/tasks/moderation_rake_spec.rb`.

**Modify**
- `app/models/user.rb` — `role` enum + `can_moderate?`.
- `app/models/flag.rb` — `status` enum, uniqueness validation, `resolve!(by:, as:)`.
- `app/models/hujah.rb` — `moderation_status` enum, `not_removed` scope, `visible_to?` early gate, trending candidate filter + cache bust, `not_removed` in `visible_to`/`timeline_for`/`visible_children_for` scopes.
- `app/models/notification.rb` — two new enum categories.
- `app/models/user_analytics.rb` — exclude removed content from aggregates.
- `app/controllers/flags_controller.rb` — idempotent create.
- `app/controllers/hujahs_controller.rb` — `not_removed` on the global feed branch.
- `app/controllers/users_controller.rb` — `not_removed` on the two profile counters.
- `app/controllers/tags_controller.rb` — `not_removed` on the tag feed base.
- `app/controllers/api/v1/hujahs_controller.rb` — `not_removed` on the JSON index.
- `app/views/debates/show.html.erb` — gate the quoted hujah body per-record.
- `app/views/shared/_navbar.html.erb` — staff-only "Moderation" menu row with pending count.
- `app/views/notifications/_notification_card.html.erb` — branches for the two new categories.
- `config/routes.rb` — the four moderation routes with explanatory comments.
- `spec/factories/users.rb` — moderator/admin traits.
- `spec/factories/flags.rb` — no change expected (status defaults to pending); verify.

## `not_removed` enforcement sites (the sweep — Slice 3)

Line numbers as of commit `550c038`. Sites that **need `not_removed`** (they list/count hujahs without per-record `visible_to?`):

| # | Site | Where |
|---|------|-------|
| E1 | Global feed branch | `app/controllers/hujahs_controller.rb:16` |
| E2 | `Hujah.timeline_for` scope (Following feed) | `app/models/hujah.rb:136-139` |
| E3 | `Hujah.visible_to` scope (feeds `Hujah.search` → search page) | `app/models/hujah.rb:109-121` |
| E4 | `Hujah.trending` candidate query + `trending:v1` id cache | `app/models/hujah.rb:170-184` (also needs a cache bust on removal, mirroring `app/models/user.rb:53,143`) |
| E5 | `Hujah#visible_children_for` (HTML thread `hujahs_controller.rb:46` + API serializer children/count `app/serializers/hujah_serializer.rb:10,54-55`) | `app/models/hujah.rb:71-76` |
| E6 | `User#visible_hujahs_for` (profile Hoojahs tab + API UserSerializer) | `app/models/user.rb:86-96` |
| E7 | Profile counters `@hoojahs_count` / `@responses_count` | `app/controllers/users_controller.rb:17-18` |
| E8 | Tag feed base + `@count` | `app/controllers/tags_controller.rb:9-13` |
| E9 | API JSON index | `app/controllers/api/v1/hujahs_controller.rb:14-15` |
| E10 | `UserAnalytics#own_hoojahs` (dashboard sums + distributions) and `#total_arguments_received` child count | `app/models/user_analytics.rb:43,62` |
| E11 | Debate transcript header quotes the hujah body raw | `app/views/debates/show.html.erb:27` (per-record gate, not the scope) |

Sites **already covered** once `visible_to?` gains the gate (per-record filtering — verify, don't change):
- Profile Responses tab Ruby filter — `app/controllers/users_controller.rb:101`.
- Notification card body render — `app/views/notifications/_notification_card.html.erb:141`.
- `HujahPolicy#show?` / `#vote?` (direct URL + voting) — `app/policies/hujah_policy.rb:6,27`; also gates replying (`create?` checks `parent.visible_to?`) and the respond composer (`hujahs#new` authorizes the parent for `show?`).
- API show — `app/controllers/api/v1/hujahs_controller.rb:39`.
- Serializer parent attribute — `app/serializers/hujah_serializer.rb:31`.

**Accepted drift (documented, not fixed):** `hashtags.hujahs_count` is a Rails counter cache on the join; a removed hujah still counts toward it (suggested-tag ordering only — no content leaks, since the tag *feed* is E8-swept). Reversing a counter cache on a status flip is machinery the spec doesn't ask for.

---

## Slice 1 — Schema + models (serial, first)

### Task 1.1: Branch + the four migrations

**Files:**
- Create: `db/migrate/<ts>_add_role_to_users.rb`
- Create: `db/migrate/<ts>_add_moderation_status_to_hujahs.rb`
- Create: `db/migrate/<ts>_add_lifecycle_to_flags.rb`
- Create: `db/migrate/<ts>_add_unique_index_to_flags.rb`
- Modify: `db/schema.rb` (generated)

Migrations have no spec of their own — the model specs in 1.2–1.5 are their tests. Verification here is that they run cleanly under strong_migrations, forward and back.

- [ ] **Step 1:** `git checkout -b content-moderation` (from a clean `master`).
- [ ] **Step 2:** Write the four migrations (`bin/rails g migration ...` for timestamps, then fill in):

```ruby
class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    # Column-add-with-default is safe on PostgreSQL 11+ (no table rewrite).
    add_column :users, :role, :integer, null: false, default: 0
  end
end
```

```ruby
class AddModerationStatusToHujahs < ActiveRecord::Migration[8.1]
  def change
    add_column :hujahs, :moderation_status, :integer, null: false, default: 0
  end
end
```

```ruby
class AddLifecycleToFlags < ActiveRecord::Migration[8.1]
  def change
    add_column :flags, :status, :integer, null: false, default: 0
    add_column :flags, :resolved_at, :datetime
    # index: false — resolved_by is never a lookup key; validate: false so the FK
    # add takes only a brief metadata lock, then validate separately (SHARE ROW
    # EXCLUSIVE, no write block) — the strong_migrations pattern.
    add_reference :flags, :resolved_by, index: false,
      foreign_key: {to_table: :users, validate: false}
    validate_foreign_key :flags, column: :resolved_by_id
  end
end
```

```ruby
class AddUniqueIndexToFlags < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Dedup before the unique index: keep the EARLIEST flag per [user, hujah]
    # (beta data — no known duplicates, but the migration must not assume that).
    # safety_assured: a bounded one-time data fix on a tiny table; strong_migrations
    # blocks raw execute by default and this is the sanctioned escape hatch.
    safety_assured do
      execute <<~SQL
        DELETE FROM flags a USING flags b
        WHERE a.user_id = b.user_id AND a.hujah_id = b.hujah_id AND a.id > b.id
      SQL
    end
    add_index :flags, [:user_id, :hujah_id], unique: true,
      name: "index_flags_on_user_and_hujah", algorithm: :concurrently
  end

  def down
    remove_index :flags, name: "index_flags_on_user_and_hujah"
  end
end
```

- [ ] **Step 3:** Run `bin/rails db:migrate` — must complete with no strong_migrations objection. Then `bin/rails db:rollback STEP=4 && bin/rails db:migrate` to prove reversibility. Then `bin/rails db:test:prepare` (schema only — never `db:prepare` on test).
- [ ] **Step 4:** `git diff db/schema.rb` — confirm exactly: `users.role`, `hujahs.moderation_status`, `flags.status/resolved_at/resolved_by_id`, the FK, and `index_flags_on_user_and_hujah` (unique).
- [ ] **Step 5:** Commit: `Moderation: add role, moderation_status, and flag lifecycle columns`

### Task 1.2: User role + `can_moderate?`

**Files:**
- Modify: `app/models/user.rb`
- Modify: `spec/factories/users.rb`
- Test: `spec/models/user_spec.rb` (append a `describe "role"` block)

- [ ] **Step 1: Write the failing tests.** Assert: a new user is `member?` by default; `moderator?`/`admin?` predicates work; `can_moderate?` is false for member, true for moderator and admin. Also add factory traits and use them in the test:

```ruby
# spec/factories/users.rb — inside factory :user
trait(:moderator) { role { :moderator } }
trait(:admin) { role { :admin } }
```

- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_spec.rb` — new examples FAIL (no `role` enum).
- [ ] **Step 3: Implement.** In `app/models/user.rb` (near the top, after the Devise block). **EXACT interface — nav, policies, and views read `can_moderate?`, never `role`:**

```ruby
enum :role, {member: 0, moderator: 1, admin: 2}, default: :member

# The ONLY capability gate the rest of the app reads (policies, nav, views).
def can_moderate? = moderator? || admin?
```

- [ ] **Step 4:** Re-run the spec file — PASS.
- [ ] **Step 5:** Commit: `Moderation: add users.role enum and can_moderate?`

### Task 1.3: Flag lifecycle

**Files:**
- Modify: `app/models/flag.rb`
- Test: `spec/models/flag_spec.rb`

- [ ] **Step 1: Write the failing tests.** Assert: default status is `pending?`; `Flag.pending` scope returns only pending flags (the enum generates it — do NOT also hand-define `scope :pending`, that raises "already defined"); a second flag by the same user on the same hujah is invalid (`validates :user_id, uniqueness: {scope: :hujah_id}`); `resolve!(by: mod, as: :dismissed)` sets `status`, `resolved_by`, and `resolved_at` in one write (freeze time or assert `resolved_at` within a delta); `resolve!(by: mod, as: :actioned)` likewise.
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/flag_spec.rb` — FAIL.
- [ ] **Step 3: Implement** in `app/models/flag.rb`. **EXACT interface:**

```ruby
belongs_to :resolved_by, class_name: "User", optional: true

enum :status, {pending: 0, dismissed: 1, actioned: 2}, default: :pending

validates :user_id, uniqueness: {scope: :hujah_id}

# One write: lifecycle transition + audit fields together, so a flag can never
# be resolved without recording who and when.
def resolve!(by:, as:)
  update!(status: as, resolved_by: by, resolved_at: Time.current)
end
```

- [ ] **Step 4:** Re-run — PASS. Also run `spec/requests/api/v1/flags_spec.rb` and `spec/requests/flag_spec.rb`: the new uniqueness validation may surface in existing specs; the API controller already branches on `save` (renders errors, 422) so it should stay green. The HTML controller still uses `create!` until Task 2.4 — if an existing spec now fails on that, note it and fix in 2.4, don't paper over here.
- [ ] **Step 5:** Commit: `Moderation: add Flag status lifecycle, uniqueness, resolve!`

### Task 1.4: Hujah `moderation_status` + `visible_to?` gate + `not_removed` scope

**Files:**
- Modify: `app/models/hujah.rb`
- Test: `spec/models/hujah_spec.rb` (append) and `spec/models/visibility_spec.rb` (append)

- [ ] **Step 1: Write the failing tests.** Assert:
  - default is `moderation_active?`; `moderation_removed?` after update.
  - `Hujah.not_removed` excludes removed records and includes active ones.
  - `visible_to?` on a **removed top-level** hujah: false for anonymous (`nil`), false for a random member, **false for the author**, true for a moderator, true for an admin.
  - `visible_to?` on a **removed reply** (parent active, reply removed): same staff-only answer — proving the gate fires before the parent-recursion branch.
  - `visible_to?` on an active reply **under a removed parent**: false for members (parent recursion), true for staff.
  - An active public hujah's `visible_to?` behavior is unchanged (regression guard).
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_spec.rb spec/models/visibility_spec.rb` — new examples FAIL.
- [ ] **Step 3: Implement** in `app/models/hujah.rb`. **EXACT interface** (prefix avoids clashing with `visibility_*` and the debate `status` enum):

```ruby
enum :moderation_status, {active: 0, removed: 1}, default: :active, prefix: :moderation

# Moderation (2026): the SQL counterpart to the visible_to? early gate below, for
# LIST surfaces that never call visible_to? per record. Every feed/count sweep
# site applies this unconditionally — staff read removed content on /moderation
# and via direct URL, not in feeds.
scope :not_removed, -> { where(moderation_status: :active) }
```

And the early gate — the **first line** of `visible_to?` (before the `parent_id` branch, so removed replies are gated too):

```ruby
def visible_to?(viewer)
  # Moderation: removed content is staff-only EVERYWHERE — including its author,
  # who learns via the moderation_removed notification instead.
  return !!viewer&.can_moderate? if moderation_removed?
  ...existing body unchanged...
end
```

Keep the existing comment block above `visible_to?` and extend it — comments carry the *why* in this codebase; don't delete them.

- [ ] **Step 4:** Re-run both spec files — PASS. Run the wider model dir (`spec/models`) to catch regressions.
- [ ] **Step 5:** Commit: `Moderation: hujah moderation_status, staff-only visible_to? gate, not_removed scope`

### Task 1.5: Notification categories

**Files:**
- Modify: `app/models/notification.rb`
- Test: `spec/models/notification_spec.rb`

- [ ] **Step 1: Write the failing test.** Assert `Notification.categories["moderation_removed"] == 14` and `Notification.categories["moderation_warning"] == 15` (the exact integers are load-bearing — the legacy API serializes them).
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/notification_spec.rb` — FAIL.
- [ ] **Step 3: Implement.** Append to the existing enum, **exactly**: `moderation_removed: 14, moderation_warning: 15` (after `follow_accepted: 13`).
- [ ] **Step 4:** Re-run — PASS.
- [ ] **Step 5:** Commit: `Moderation: add moderation_removed and moderation_warning notification categories`

---

## Slice 2 — Authorization + routes + controller + queue page (parallel-safe with Slice 3)

### Task 2.1: ModerationPolicy

**Files:**
- Create: `app/policies/moderation_policy.rb`
- Test: `spec/policies/moderation_policy_spec.rb`

- [ ] **Step 1: Write the failing tests.** For each of `index?/dismiss?/remove?/warn?`: nil user denied, member denied, moderator allowed, admin allowed. Instantiate directly (`described_class.new(user, :moderation)`) like the other policy specs.
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/policies/moderation_policy_spec.rb` — FAIL (uninitialized constant).
- [ ] **Step 3: Implement — EXACT:**

```ruby
# Headless policy: Pundit resolves `authorize :moderation, :<action>?` here.
# Purely "is this user staff" — there is no per-record nuance to encode.
class ModerationPolicy < ApplicationPolicy
  def index? = !!user&.can_moderate?

  def dismiss? = !!user&.can_moderate?

  def remove? = !!user&.can_moderate?

  def warn? = !!user&.can_moderate?
end
```

- [ ] **Step 4:** Re-run — PASS.
- [ ] **Step 5:** Commit: `Moderation: headless ModerationPolicy staff gate`

### Task 2.2: Routes + `moderation#index` + queue views

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/moderation_controller.rb`
- Create: `app/views/moderation/index.html.erb`, `app/views/moderation/_flagged_hujah.html.erb`
- Test: `spec/requests/moderation_spec.rb`

- [ ] **Step 1: Write the failing tests** (`spec/requests/moderation_spec.rb`, use the existing `sign_in`/`login_as` helpers; factory password is `hoojah88`). Assert for `GET /moderation`:
  - anonymous → redirected (Devise `authenticate_user!` → login).
  - member → 403-or-redirect-back with alert (the Pundit rescue renders redirect for HTML — assert `redirect_to` + flash alert "Not allowed.").
  - moderator → 200; body includes the flagged hujah's text and the report count; a hujah with only **resolved** flags does NOT appear; ordering is oldest-pending-first (create two flagged hujahs with staggered flag `created_at` and assert order of appearance in `response.body`).
  - a **removed** hujah whose flags are still pending still appears (staff queue is exempt from `not_removed` by construction — it queries by flags, not the swept scopes).
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/moderation_spec.rb` — FAIL (no route).
- [ ] **Step 3: Implement routes** — add to `config/routes.rb` after the `/blocks` route (the own-list region), comments included (per the routes-file convention; in this codebase ERB comments compile Tailwind classes but routes.rb is Ruby — prose is safe). **EXACT route lines and names:**

```ruby
  # Moderator review queue + actions (2026 moderation). Staff-only via the headless
  # ModerationPolicy; own-list style (no id in the index URL — the queue is global,
  # not user-scoped). HTML/Turbo WRITE actions, so they live on MAIN routes (CSRF
  # enforced), never under Api::V1. :slug is the flagged hujah's friendly_id.
  get "/moderation", to: "moderation#index", as: :moderation
  patch "/moderation/:slug/dismiss", to: "moderation#dismiss", as: :dismiss_moderation
  delete "/moderation/:slug/remove", to: "moderation#remove", as: :remove_moderation
  post "/moderation/:slug/warn", to: "moderation#warn", as: :warn_moderation
```

**Controller** (index only in this task) — **EXACT shape:**

```ruby
class ModerationController < ApplicationController
  before_action :authenticate_user!

  # Hujahs with >= 1 pending flag, oldest pending report first, one row per hujah.
  # GROUP BY + aggregate select; includes(:user, :flags) preloads via separate
  # queries so the grouping is undisturbed. pagy(:countless, ...) per house rule.
  def index
    authorize :moderation, :index?
    base = Hujah.joins(:flags).where(flags: {status: Flag.statuses[:pending]})
      .group("hujahs.id")
      .select("hujahs.*, COUNT(flags.id) AS pending_flag_count, MIN(flags.created_at) AS earliest_flagged_at")
      .order(Arel.sql("MIN(flags.created_at) ASC"))
      .includes(:user, :flags)
    @pagy, @hujahs = pagy(:countless, base)
  end
end
```

**Views.** `index.html.erb`: heading, a pending count element with **exact id** `moderation-pending-count` (the stream templates replace it), the item list rendering `_flagged_hujah` per hujah, `ui/_empty_state` (`message: "Nothing to review."`, `icon: "shield"`) when empty, and the house load-more pattern only if trivially reusable — otherwise a plain list is fine (queue length is small; don't gold-plate).

`_flagged_hujah.html.erb` — one item, **wrapped in `dom_id(hujah, :moderation_item)`** (frozen: the stream templates and system spec target it). Use the card layout partial correctly:

```erb
<%= render layout: "ui/card", locals: {id: dom_id(hujah, :moderation_item), padded: true, class: "mb-3"} do %>
  ...
<% end %>
```

Content: `ui/_avatar` (size `:row`) + author name/@handle, `format_body(hujah.body)` preview (truncate long bodies with `truncate(strip_tags(...), length: 200)` — do not render unbounded), "Reply to …" line when `hujah.parent_id`, pending report count + per-reason breakdown computed from the preloaded association in Ruby (`hujah.flags.select(&:pending?).group_by(&:subject)` — no extra query), the earliest flag timestamp, and three `button_to` actions. **Exact buttons** (labels and paths are frozen — request/system specs click them by name):

```erb
<%= button_to "Dismiss", dismiss_moderation_path(hujah.slug), method: :patch,
      class: ds_button_classes(tone: "grey", size: :sm) %>
<%= button_to "Warn author", warn_moderation_path(hujah.slug), method: :post,
      class: ds_button_classes(tone: "neutral", size: :sm) %>
<%= button_to "Remove", remove_moderation_path(hujah.slug), method: :delete,
      class: ds_button_classes(tone: "disagree", size: :sm),
      form: {data: {turbo_confirm: "Remove this hoojah for everyone, including its author?"}} %>
```

All tones (`grey`, `neutral`, `disagree`) are already in the `@source inline(...)` safelist — introduce no new interpolated classes, and keep ERB comments free of concrete class names.

- [ ] **Step 4:** Re-run `spec/requests/moderation_spec.rb` (index examples) — PASS.
- [ ] **Step 5:** Commit: `Moderation: routes, queue controller index, queue views`

### Task 2.3: dismiss / remove / warn actions + Turbo Streams

**Files:**
- Modify: `app/controllers/moderation_controller.rb`
- Create: `app/views/moderation/dismiss.turbo_stream.erb`, `remove.turbo_stream.erb`, `warn.turbo_stream.erb`
- Create: `app/helpers/moderation_helper.rb`
- Test: `spec/requests/moderation_spec.rb` (append)

- [ ] **Step 1: Write the failing tests.** For each action (member-denied + moderator-allowed, and with a hujah carrying 2 pending flags from different users + 1 already-dismissed flag):
  - **dismiss** (PATCH): both pending flags become `dismissed` with `resolved_by == moderator` and `resolved_at` set; the already-resolved flag is untouched; hujah stays `moderation_active?`; **no** notification created; HTML fallback redirects to `/moderation`; with `Accept: text/vnd.turbo-stream.html` responds turbo-stream and body includes `dom_id(hujah, :moderation_item)` (removal) and `moderation-pending-count`.
  - **remove** (DELETE): hujah becomes `moderation_removed?`; pending flags become `actioned`; exactly one `Notification` created with `category: "moderation_removed"`, `user_id: hujah.user_id`, `hujah_id: hujah.id`, and **`subject_user_id: nil`** (never identify the moderator — same shape as the secret-ballot rule).
  - **warn** (POST): hujah stays `moderation_active?`; pending flags become `actioned`; one `moderation_warning` notification with the same field shape.
  - idempotence guard: a second dismiss on the same slug still 200s/redirects (zero pending flags to resolve — must not raise).
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/moderation_spec.rb` — new examples FAIL.
- [ ] **Step 3: Implement.** Controller additions — **EXACT shape:**

```ruby
  before_action :set_hujah, except: :index

  # Resolve every pending report; content untouched.
  def dismiss
    authorize :moderation, :dismiss?
    resolve_pending_flags(as: :dismissed)
    respond_resolved
  end

  # Hide the hujah from everyone but staff + tell the author. One transaction:
  # a half-applied removal (hidden but unresolved flags, or vice versa) must not exist.
  def remove
    authorize :moderation, :remove?
    ActiveRecord::Base.transaction do
      @hujah.update!(moderation_status: :removed)
      resolve_pending_flags(as: :actioned)
      Notification.create!(user_id: @hujah.user_id, category: :moderation_removed, hujah_id: @hujah.id)
    end
    respond_resolved
  end

  # Content untouched; author notified; reports closed as actioned.
  def warn
    authorize :moderation, :warn?
    ActiveRecord::Base.transaction do
      resolve_pending_flags(as: :actioned)
      Notification.create!(user_id: @hujah.user_id, category: :moderation_warning, hujah_id: @hujah.id)
    end
    respond_resolved
  end

  private

  def set_hujah
    @hujah = Hujah.friendly.find(params[:slug])
  end

  def resolve_pending_flags(as:)
    @hujah.flags.pending.find_each { |flag| flag.resolve!(by: current_user, as: as) }
  end

  def respond_resolved
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to moderation_path, status: :see_other }
    end
  end
```

The three turbo_stream templates are identical in shape (write each out — they may be read independently):

```erb
<%= turbo_stream.remove dom_id(@hujah, :moderation_item) %>
<%= turbo_stream.replace "moderation-pending-count" do %>
  <span id="moderation-pending-count"><%= pending_moderation_count %></span>
<% end %>
```

`app/helpers/moderation_helper.rb` — **EXACT interface** (the navbar reuses it in Task 4.1):

```ruby
module ModerationHelper
  # Hujahs awaiting review (not raw reports): distinct flagged hujahs with a
  # pending flag. Computed on read — queue volume at beta scale doesn't earn a cache.
  def pending_moderation_count
    Flag.pending.distinct.count(:hujah_id)
  end
end
```

- [ ] **Step 4:** Re-run the request spec — PASS. Also `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/policies spec/models/flag_spec.rb`.
- [ ] **Step 5:** Commit: `Moderation: dismiss, remove, warn actions with Turbo Stream queue updates`

### Task 2.4: FlagsController idempotency

**Files:**
- Modify: `app/controllers/flags_controller.rb`
- Test: `spec/requests/flag_spec.rb` (append)

- [ ] **Step 1: Write the failing test.** Signed-in user flags the same hujah twice with different subjects: second POST does **not** raise/500, `Flag.count` changes by 0 on the second call, and the single flag's `subject` is updated to the second reason. Keep the two existing examples green (they pin the turbo-stream close-dialog contract).
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/flag_spec.rb` — FAIL (RecordInvalid on the new uniqueness validation).
- [ ] **Step 3: Implement** — replace the `create!` line, keeping the rest of the action byte-identical:

```ruby
    # Idempotent under the [user, hujah] unique index: a re-flag updates the
    # reason instead of raising. Deliberately does NOT touch `status` — a re-flag
    # of already-reviewed content does not re-open the report (spec'd behavior).
    flag = current_user.flags.find_or_initialize_by(hujah: @hujah)
    flag.update!(subject: flag_params[:subject])
```

- [ ] **Step 4:** Re-run — PASS. Also run `spec/requests/api/v1/flags_spec.rb` (API stays non-idempotent by design — it branches on `save` and 422s a duplicate; that is acceptable legacy-API behavior, do not change it).
- [ ] **Step 5:** Commit: `Moderation: make HTML flag create idempotent per user and hujah`

---

## Slice 3 — Enforcement sweep (parallel-safe with Slice 2)

### Task 3.1: List surfaces — feed, timeline, search, children, profile, tags, API index

**Files:**
- Modify: `app/models/hujah.rb` (E2 `timeline_for`, E3 `visible_to`, E5 `visible_children_for`)
- Modify: `app/models/user.rb` (E6 `visible_hujahs_for`)
- Modify: `app/controllers/hujahs_controller.rb` (E1)
- Modify: `app/controllers/users_controller.rb` (E7)
- Modify: `app/controllers/tags_controller.rb` (E8)
- Modify: `app/controllers/api/v1/hujahs_controller.rb` (E9)
- Test: Create `spec/requests/moderation_visibility_spec.rb`

- [ ] **Step 1: Write the failing tests** in one request spec file. Fixture: a public author with one removed top-level hujah (distinctive body string), one active hujah, and one removed reply under an active parent. Assert:
  - **Global feed** `GET /` (anonymous and signed-in member): removed body absent, active body present.
  - **Following feed** `GET /?filter=following` as a follower: removed body absent.
  - **Search** `GET /search?q=<term>`: removed hujah never matches.
  - **Thread** `GET /hoojah/<parent-slug>`: removed reply's body absent for a member; parent still renders.
  - **Profile** `GET /u/<author>`: removed hujah absent from the Hoojahs tab, and `@hoojahs_count`/`@responses_count` shown on the page exclude removed rows (assert the rendered count text).
  - **Tag feed** `GET /t/<name>`: removed hujah absent and the count excludes it.
  - **API index** `GET /api/v1/hoojah/index`: removed hujah absent from JSON.
  - **Author lockout**: the author GETs their own removed hujah's show URL → redirected with alert (Pundit rescue), and it is absent from their own profile tab.
  - **Staff access**: a moderator GETs the removed hujah's show URL → 200 (this is where "remains visible to staff" lives — feeds exclude removed content for everyone, including staff; the queue and direct URL are the staff surfaces).
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/moderation_visibility_spec.rb` — feed/search/profile/tag/API examples FAIL (show-URL examples may already pass off Slice 1's gate — fine).
- [ ] **Step 3: Implement** — mechanical, one `.not_removed` per site, each with a one-line `# Moderation:` comment naming the sweep:
  - `hujah.rb` `timeline_for`: `where(parent_id: nil).not_removed.where(user_id: ...)`.
  - `hujah.rb` `visible_to` scope: `base = where(parent_id: nil).not_removed.joins(:user)` (covers `Hujah.search`).
  - `hujah.rb` `visible_children_for`: `scope = children.not_removed.includes(:user).order(updated_at: :desc)` (covers the HTML thread AND the API serializer's children list + count).
  - `user.rb` `visible_hujahs_for`: `base.not_removed.where(parent_id: nil)...` on the final line.
  - `hujahs_controller.rb:16` global branch: `Hujah.not_removed.where(parent_id: nil)...`.
  - `users_controller.rb:17-18`: `@user.hujahs.not_removed.where(parent_id: nil).count` / `@user.hujahs.not_removed.where.not(parent_id: nil).count`.
  - `tags_controller.rb:9`: `@tag.hujahs.not_removed.where(parent_id: nil)...`.
  - `api/v1/hujahs_controller.rb:14`: `Hujah.not_removed.where(parent_id: nil)...`.
- [ ] **Step 4:** Re-run the visibility spec — PASS. Then run the neighboring guards: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/hujahs_index_spec.rb spec/requests/timeline_spec.rb spec/requests/search_spec.rb spec/requests/tags_spec.rb spec/requests/profile_spec.rb spec/requests/hujahs_show_spec.rb spec/requests/api spec/serializers`.
- [ ] **Step 5:** Commit: `Moderation: not_removed sweep across feed, timeline, search, thread, profile, tags, API index`

### Task 3.2: Trending — candidates + cache bust

**Files:**
- Modify: `app/models/hujah.rb`
- Test: `spec/models/hujah_trending_spec.rb` (append)

- [ ] **Step 1: Write the failing tests.** (Mirror the existing private-author trending tests in this file — they show the cache-handling idiom.) Assert: a removed hujah never enters trending candidates; and — the T-1-shaped case — a hujah already in the cached trending ids stops appearing **immediately** after removal (the cache is busted on the moderation flip, not left to expire for up to 15 min).
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_trending_spec.rb` — FAIL.
- [ ] **Step 3: Implement** in `app/models/hujah.rb`:
  - In `self.trending`'s candidate query: `where(parent_id: nil).not_removed.where("hujahs.updated_at > ?", ...)`.
  - Cache bust, mirroring `User#bust_trending_cache` (user.rb:53):

```ruby
after_update_commit :bust_trending_cache, if: -> { saved_change_to_moderation_status? }

# private
def bust_trending_cache = Rails.cache.delete("trending:v1")
```

- [ ] **Step 4:** Re-run + `spec/requests/trending_spec.rb` — PASS.
- [ ] **Step 5:** Commit: `Moderation: exclude removed hujahs from trending and bust the id cache on removal`

### Task 3.3: Counters — analytics + debate transcript quote

**Files:**
- Modify: `app/models/user_analytics.rb`
- Modify: `app/views/debates/show.html.erb`
- Test: `spec/models/user_analytics_spec.rb` (append), `spec/requests/debate_spec.rb` (append)

- [ ] **Step 1: Write the failing tests.**
  - Analytics: a user with one active and one removed hujah (both with votes/children) — `total_votes_received`, `total_arguments_received`, and `distributions` all exclude the removed hujah's contribution (removed content is hidden from its author, so the author's dashboard must not count it either).
  - Debate transcript: a concluded (publicly readable) debate whose hujah is then removed — `GET /debates/<slug>` as a member does NOT include the hujah's body text; as a moderator it does. (The back-link to the hujah may remain; it dead-ends at the authorized show gate.)
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_analytics_spec.rb spec/requests/debate_spec.rb` — new examples FAIL.
- [ ] **Step 3: Implement.**
  - `user_analytics.rb`: `own_hoojahs` → `Hujah.not_removed.where(user_id: user.id)`; `total_arguments_received` → `Hujah.not_removed.where(parent_id: own_hoojahs.select(:id)).count`.
  - `debates/show.html.erb:27`: gate the quote per-record — replace the unconditional body with:

```erb
On “<%= @debate.hujah.visible_to?(current_user) ? strip_tags(@debate.hujah.body) : "a removed hoojah" %>”
```

  (This also closes the pre-existing sliver where a restricted hujah's body leaked through a concluded-public debate header — same gate, free fix. If any existing debate spec pins the old unconditional string, update it to build a visible hujah, not to weaken the gate.)
- [ ] **Step 4:** Re-run both files + `spec/requests/analytics_spec.rb` — PASS.
- [ ] **Step 5:** Commit: `Moderation: exclude removed content from analytics; gate debate transcript quote`

### Task 3.4: Slice 3 regression gate

- [ ] **Step 1:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec --exclude-pattern "spec/system/**/*"` (coordinate with the Slice 2 agent — one suite at a time on the shared DB). Fix any fallout in this slice's files only.
- [ ] **Step 2:** `bundle exec standardrb` — clean (use `--fix` for layout).
- [ ] **Step 3:** Commit any fixes: `Moderation: enforcement-sweep regression fixes`

---

## Slice 4 — Nav + notifications + reply-flag verification + system spec (after Slices 2 AND 3)

### Task 4.1: Navbar "Moderation" entry

**Files:**
- Modify: `app/views/shared/_navbar.html.erb`
- Test: `spec/requests/navigation_spec.rb` (append)

- [ ] **Step 1: Write the failing tests.** As a moderator, `GET /` body includes a "Moderation" link to `/moderation` and (with pending flags present) the pending count; as a plain member and as anonymous, no "Moderation" link.
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/navigation_spec.rb` — FAIL.
- [ ] **Step 3: Implement.** Inside the signed-in `<details>` avatar menu, after the "Dashboard" row (this navbar's design rule is "8px dot, never a count badge" **on the bar** — so the entry is a menu row, with the count as text in the row, which satisfies the spec's badge requirement without breaking the house rule):

```erb
<% if current_user.can_moderate? %>
  <%= link_to moderation_path, class: ds_menu_item_classes do %>
    Moderation
    <% count = pending_moderation_count %>
    <% if count > 0 %>
      <span id="nav-moderation-count" class="ml-1 text-xs text-grey">(<%= count %>)</span>
    <% end %>
  <% end %>
<% end %>
```

Guard: this runs `pending_moderation_count` only for staff, so ordinary page loads pay nothing.
- [ ] **Step 4:** Re-run — PASS.
- [ ] **Step 5:** Commit: `Moderation: staff-only navbar entry with pending count`

### Task 4.2: Notification cards for the two new categories

**Files:**
- Modify: `app/views/notifications/_notification_card.html.erb`
- Test: `spec/requests/notifications_spec.rb` (append)

- [ ] **Step 1: Write the failing tests.** Render `/notifications` for an author holding one of each: `moderation_removed` renders "Your hoojah was removed by a moderator for violating community guidelines"; `moderation_warning` renders "A moderator has issued a warning about your hoojah" **and** (since the hujah is still visible to its author) the tappable body preview linking through the existing mark-read `button_to`. For `moderation_removed`, assert the hujah body is NOT in the response (the existing `visible_to?` branch suppresses it — the author cannot see removed content) and the row still carries a "Mark as read" affordance.
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/notifications_spec.rb` — FAIL (falls to the bell/else branches).
- [ ] **Step 3: Implement.** In the icon/tone `case` add (reuse icon names already proven in this file — `lucide_icon` raises on unknown names):

```erb
when "moderation_removed" then ["x-circle", "disagree"]
when "moderation_warning" then ["alert-triangle", "neutral"]
```

In the copy `case` add the two branches with the exact copy above. No new interpolated tone values — `disagree`/`neutral` are already in the `-soft` safelist entry. Add no moderator identity anywhere (these notifications carry no `subject_user_id` by construction — Task 2.3).
- [ ] **Step 4:** Re-run — PASS. Also run `spec/system/notifications_spec.rb` later with the system batch.
- [ ] **Step 5:** Commit: `Moderation: notification cards for removal and warning`

### Task 4.3: Verify the flag dialog reaches reply hujahs

**Files:**
- Test: `spec/requests/hujahs_show_spec.rb` (append)
- Modify (only if the test fails): `app/views/hujahs/show.html.erb`

- [ ] **Step 1: Write the test.** Signed-in member GETs a **reply** hujah's own show page (`/hoojah/<reply-slug>`): body includes `dom_id(reply, :flag_dialog)` and the "Flag this hoojah" trigger. This is the canonical flag surface for replies — the thread's `_child_card` is a single anchor linking to this page and deliberately carries no menu (its response-filter markup is FROZEN; a nested menu inside an `<a>` is invalid HTML). Do NOT add a menu to `_child_card`.
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/hujahs_show_spec.rb`. Expected: PASS already (`hujahs/show` renders `_flag_dialog` for `@hujah` unconditionally). If it fails, fix `show.html.erb`'s conditional so the More-actions menu (and flag row) renders for child hujahs too — change nothing else.
- [ ] **Step 3:** Commit: `Moderation: pin flag dialog availability on reply hujahs`

### Task 4.4: System spec — the moderator flow

**Files:**
- Test: Create `spec/system/moderation_spec.rb`

- [ ] **Step 1: Write the spec** (`js: true`, Cuprite, follow `spec/system/flag_spec.rb`'s login idiom). One flow: member flags a hujah (or seed the flag via factory); moderator signs in, opens `/moderation`, sees the item, clicks "Remove" and accepts the `turbo_confirm`; the item leaves the queue without a page reload (`expect(page).not_to have_css("##{dom_id(hujah, :moderation_item)}")`); then the member signs in and the hujah is absent from the feed and its direct URL redirects with the "Not allowed." alert.
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/moderation_spec.rb` — PASS (implementation exists; if it fails, the failure is real — debug the feature, not the spec).
- [ ] **Step 3: Tailwind sanity.** `bin/rails tailwindcss:build` from the repo root (never elsewhere — `@source not` paths are cwd-relative), then confirm no new class was silently missing: grep the built bundle for one representative used class per new view. If any ERB comment in the new files names a concrete utility class, reword it, rebuild, and md5-compare per CLAUDE.md.
- [ ] **Step 4:** Commit: `Moderation: system spec for the remove flow`

---

## Slice 5 — Rake task (any time after Slice 1)

### Task 5.1: `moderation:promote` / `moderation:demote`

**Files:**
- Create: `lib/tasks/moderation.rake`
- Test: Create `spec/tasks/moderation_rake_spec.rb`

- [ ] **Step 1: Write the failing tests.** Load tasks once (`Rails.application.load_tasks` guarded by `Rake::Task.task_defined?("moderation:promote")`), then: `moderation:promote[username]` flips a member to `moderator?`; `moderation:demote[username]` flips back to `member?`; unknown username raises `ActiveRecord::RecordNotFound`. Call `Rake::Task["moderation:promote"].execute(Rake::TaskArguments.new([:username], [user.username]))` (execute, not invoke — invoke memoizes and breaks the second example).
- [ ] **Step 2:** Run `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/tasks/moderation_rake_spec.rb` — FAIL.
- [ ] **Step 3: Implement — EXACT:**

```ruby
namespace :moderation do
  desc "Promote a user to moderator: bin/rails 'moderation:promote[username]'"
  task :promote, [:username] => :environment do |_t, args|
    user = User.find_by!(username: args.fetch(:username))
    user.update!(role: :moderator)
    puts "#{user.username} is now a moderator"
  end

  desc "Demote a user to member: bin/rails 'moderation:demote[username]'"
  task :demote, [:username] => :environment do |_t, args|
    user = User.find_by!(username: args.fetch(:username))
    user.update!(role: :member)
    puts "#{user.username} is now a member"
  end
end
```

- [ ] **Step 4:** Re-run — PASS. `bundle exec standardrb` (lib/ is linted).
- [ ] **Step 5:** Commit: `Moderation: promote/demote rake tasks`

---

## Finish line (orchestrator-driven)

- [ ] `bin/ci` — full definition of green (gates + Tailwind build + full suite incl. system specs). Shared-DB rule: nothing else running.
- [ ] Review passes on the whole diff: rails-simplifier, better-stimulus (should find nothing — this feature adds **no** Stimulus; `turbo_confirm` and the existing `dialog` controller cover the UI), rails-security-auditor. Batch fixes, re-run `bin/ci`.
- [ ] Merge `content-moderation` → `master` (no PR, per spec), push.

---

## Self-review — spec requirement → task map

| Spec requirement | Task |
|---|---|
| `users.role` enum + `can_moderate?` sole gate | 1.1, 1.2 |
| Flag `status` enum, `resolve!(by:, as:)`, uniqueness + unique index (dedup-safe), `pending` scope (enum-generated) | 1.1, 1.3 |
| `hujahs.moderation_status` enum with `:moderation` prefix | 1.1, 1.4 |
| `visible_to?` early staff-only gate (before parent recursion) | 1.4 |
| `not_removed` scope + list-surface sweep (feed, timeline, search, children, profile lists, tag feed, API index) | 1.4, 3.1 |
| Trending candidates + 15-min id cache handled (bust on removal) | 3.2 |
| Counters that would count removed content (profile counts, analytics; hashtag counter-cache drift documented as accepted) | 3.1 (E7), 3.3 (E10) |
| Notification categories 14/15, author-facing, no moderator identity | 1.5, 2.3 |
| Notification cards with icon + copy, link/affordance behavior for removed vs warned | 4.2 |
| Headless `ModerationPolicy`, every action `authorize`d exactly once | 2.1, 2.2, 2.3 |
| Four MAIN routes with exact names (`moderation`, `dismiss_moderation`, `remove_moderation`, `warn_moderation`), commented | 2.2 |
| `index` queue: pending-flagged hujahs, eager loading, oldest-pending-first, pagy countless | 2.2 |
| dismiss / remove (transactional) / warn semantics + Turbo-Stream + HTML fallback | 2.3 |
| `FlagsController#create` idempotent | 2.4 |
| Queue UI on `ui/_card` layout partial, `ds_button_classes` tones, `turbo_confirm` on Remove, empty state | 2.2 |
| Nav entry gated on `can_moderate?` with pending count (`Flag.pending.distinct.count(:hujah_id)`) | 2.3 (helper), 4.1 |
| Flag dialog on replies verified | 4.3 |
| Model/policy/request/feed-visibility/system test coverage | 1.2–1.5, 2.1–2.4, 3.1–3.3, 4.4 |
| No new Stimulus; `turbo_confirm` for destructive action | 2.2 (by construction) |
| Tailwind safelist discipline (no new interpolations; md5 check) | 2.2, 4.4 |
| `bin/ci` green; three review passes; merge to master, no PR | Finish line |
| Rake promote/demote | 5.1 |

Placeholder scan: none — every code-bearing step carries its code; test steps state exact behaviors + run commands per the delegation contract. Interface consistency check: `can_moderate?`, `resolve!(by:, as:)`, `not_removed`, enum values `{member:0, moderator:1, admin:2}` / `{pending:0, dismissed:1, actioned:2}` / `{active:0, removed:1}` / categories `14/15`, route names, `dom_id(hujah, :moderation_item)`, `moderation-pending-count`, and `pending_moderation_count` are each defined once and referenced identically throughout.
