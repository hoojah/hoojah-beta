# Plan: Slice C — Follow-system gaps (Everything) — 2026-08-26

Implements the **Slice C** section of
`docs/superpowers/specs/2026-08-26-navbar-hovercard-follows-design.md` (authoritative). All 8
gaps, owner-approved, including the high-risk counter-cache.

## How to execute this plan

- One task per subagent, **in order**, each followed by spec run + independent review before the
  next starts. Tasks touch mostly-disjoint file sets; where two tasks touch the same file the
  later task builds on the earlier one's landed state (called out inline).
- Each task ends with the **targeted** specs it names, green, plus
  `bundle exec standardrb` clean on the files it touched. Full `bin/ci` runs once, at the end
  (Task 9). **Shared Postgres test DB:** never run two suites concurrently — targeted specs only
  while working (`RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec <files>`).
- All new routes are **main HTML/Turbo routes, never `Api::V1`** (CSRF stays on; `button_to`
  carries the token). Every new non-Devise action calls `authorize` or `skip_authorization`
  exactly once (`verify_authorized` raises otherwise).
- StandardRB: `db/schema.rb`, `db/migrate/**` excluded — do not "fix" migration formatting.
  Brakeman + bundler-audit must stay clean. prosopite is **log-only** — do not turn it into a
  failing gate; a new N+1 in `log/prosopite.log` is worth fixing but not a blocker.
- Commit per task: **plain imperative subject** (these are not numbered roadmap slices — no
  `Slice N Task X.Y:` prefix), **no Claude/Anthropic branding**, no `Co-Authored-By`. Never
  `git commit --amend` unless HEAD is verifiably your own commit.
- Tailwind: every class in this slice can and should be a **literal in ERB** — no interpolated
  stance/tone classes are introduced, so **no new `@source inline(...)` safelist entries**.
  Remember ERB comments are scanned as text: never name a concrete utility class in an ERB
  comment you aren't also using.

## Ordering rationale

The counter-cache (gap 8) goes **first** (Tasks 1–2): every later task either mutates follows
(remove-follower, bulk accept, expiry) or reads counts (inbox, turbo streams, read-flip). With
the columns and the `Follow`-model maintenance landed first, every subsequent mutation path that
routes through normal AR `create`/`update!`/`destroy` inherits correct counts *for free* from the
model callbacks — the only paths needing bespoke handling are the two callback-skipping bulk
writes, and both are rewritten by this plan (block `delete_all` gets explicit in-transaction
adjustment in Task 2; the private→public `update_all` is replaced by per-row `update!` in
Task 3, which routes it through the callbacks). Doing the counter-cache last instead would force
Tasks 3–8 to each be revisited for count correctness — strictly more risk.

The **read flip** (moving views/controllers off `.followers.size` onto the columns) is
deliberately **last** (Task 9): the drift-check spec from Task 2 guards the columns through
Tasks 3–8 while all user-visible surfaces still render the always-correct computed counts. If
drift appears mid-slice, users never saw a wrong number.

Known interim state, accepted: between Task 2 and Task 3, `UsersController#update`'s
private→public `update_all(status: :accepted)` still skips callbacks, so that one path would
drift counters. No shipped surface reads the columns yet (read flip is Task 9), Task 3 lands
immediately after, and Task 2's drift spec does not exercise that path (Task 3's specs do).

---

## Task 1 — Counter-cache columns + batched backfill (migrations only)

**Rationale.** Gap 8's schema foundation. Two separate migrations because `strong_migrations` is
active and its documented safe pattern is *add column with default* in one DDL migration, then
*backfill data* in a second, non-DDL-transactional, batched migration (house precedent:
`db/migrate/20260805145333_backfill_new_vote_subject_user.rb` uses `disable_ddl_transaction!`
for a data-only backfill).

**Files.**
- Create `db/migrate/<ts>_add_follow_counter_caches_to_users.rb`
- Create `db/migrate/<ts+1>_backfill_follow_counter_caches.rb`
- `db/schema.rb` regenerates (do not hand-edit).

**Change.**

Migration 1 (plain, transactional — adding a column with a constant default is a fast/safe
operation on this Postgres, and strong_migrations allows it):

```ruby
class AddFollowCounterCachesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :followers_count, :integer, default: 0, null: false
    add_column :users, :following_count, :integer, default: 0, null: false
  end
end
```

Migration 2 — data-only backfill, `disable_ddl_transaction!`, batched via `in_batches`, raw SQL
subqueries against `follows` so the migration does not couple to the `Follow` model or its enum
(`status = 1` is `accepted` — integer hardcoded on purpose, same reasoning as the
`backfill_new_vote_subject_user` migration's literal `category: 4`):

```ruby
class BackfillFollowCounterCaches < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Model-free relation: this migration must not depend on app code.
    users = Class.new(ActiveRecord::Base) { self.table_name = "users" }
    users.in_batches(of: 1000) do |batch|
      batch.update_all(<<~SQL)
        followers_count = (SELECT COUNT(*) FROM follows
                            WHERE follows.followed_id = users.id AND follows.status = 1),
        following_count = (SELECT COUNT(*) FROM follows
                            WHERE follows.follower_id = users.id AND follows.status = 1)
      SQL
    end
  end

  def down
    # Columns are dropped by reverting migration 1; nothing to undo here.
  end
end
```

Run `bin/rails db:migrate` then `bin/rails db:test:prepare` (schema-only — never `db:prepare`
on the test DB; it seeds).

**Specs.** None new in this task (migration correctness is proven by Task 2's drift spec, which
compares columns to the accepted-only scopes on freshly built data). Confirm the whole existing
follow surface still passes: `spec/models/follow_spec.rb`, `spec/models/follow_flow_spec.rb`,
`spec/requests/follow_spec.rb`, `spec/requests/follow_request_spec.rb`.

**Acceptance.**
- Both columns exist: integer, `default: 0`, `null: false`.
- Backfill migration carries `disable_ddl_transaction!` and batches; no model constant
  references; no DDL in migration 2.
- `bin/rails db:migrate` runs clean with strong_migrations active (no `safety_assured` needed —
  if strong_migrations raises, the shape is wrong; fix the shape, don't blanket-`safety_assured`).
- Existing targeted specs green.

---

## Task 2 — Follow model counter maintenance + block adjustment + drift-check spec

**Rationale.** The heart of gap 8. Explicit model logic, **not** Rails' built-in
`counter_cache:` (which counts every row; ours are accepted-only). Also extracts
`dismiss_request_notification` from `FollowRequestsController` into the `Follow` model so
Tasks 3, 4 (expiry), and 8 (cancel-pending) can reuse one implementation instead of three
copies.

**Files.**
- Edit `app/models/follow.rb`
- Edit `app/controllers/blocks_controller.rb`
- Edit `app/controllers/follow_requests_controller.rb` (delegate the private helper to the model)
- Create `spec/models/follow_counter_cache_spec.rb`
- Extend `spec/models/follow_spec.rb` (dismissal method), `spec/models/block_spec.rb` (counts)

**Change — `app/models/follow.rb`.**

Add three callbacks. Use **in-transaction** callbacks (`after_create` / `after_update` /
`after_destroy`), NOT `_commit` variants: the counts must roll back with the row. This matters
concretely for `FollowsController#create`'s `RecordNotUnique` race — the losing INSERT's
transaction rolls back, and an `after_create_commit` would never fire but an in-transaction
increment must also vanish, which `after_create` guarantees. Keep the existing notification
callbacks on `_commit` exactly as they are — notifications are outbound side effects,
counters are transactional state; the split is deliberate and should be said in a comment.

```ruby
after_create :increment_counters, if: :accepted?
after_update :adjust_counters_for_status_change, if: :saved_change_to_status?
after_destroy :decrement_counters, if: :accepted?
```

with private methods using `User.update_counters` (atomic SQL `UPDATE ... SET x = x + n`, no
callbacks/validations — exactly right here):

```ruby
def increment_counters
  User.update_counters(followed_id, followers_count: 1)
  User.update_counters(follower_id, following_count: 1)
end

def decrement_counters
  User.update_counters(followed_id, followers_count: -1)
  User.update_counters(follower_id, following_count: -1)
end

def adjust_counters_for_status_change
  # pending→accepted is the only transition the app performs; accepted→pending is
  # handled anyway so a future/console write can't silently corrupt the counts.
  accepted? ? increment_counters : decrement_counters
end
```

Also add the extracted public method (verbatim behaviour of the controller's current private
helper — `follow_requests_controller.rb:29–32`):

```ruby
# The follow_request notification for this row has been actioned (accepted,
# declined, cancelled, or expired) — remove it so its card disappears. Returns the
# destroyed rows so a Turbo caller can also remove their cards from the DOM.
def dismiss_request_notification!
  Notification.where(user_id: followed_id, subject_user_id: follower_id,
    category: :follow_request).destroy_all
end
```

`FollowRequestsController`'s private `dismiss_request_notification` becomes a one-line delegate
(`@follow.dismiss_request_notification!`) — keep the method so this task doesn't touch the
response shape (Task 6 does that).

Update the header comment block on `Follow` to document the counter contract (accepted-only,
in-transaction, and that `delete_all`/`update_all` callers own their own adjustment — naming
`BlocksController` and pointing at this plan's invariant checklist).

**Change — `app/controllers/blocks_controller.rb`.**

`create`'s transaction currently does `Follow.where(...).delete_all` (comment says it's safe
*because* Follow has no destroy callbacks — that comment is now false and must be rewritten).
Keep `delete_all` (one statement, still skips the *notification* callbacks on purpose) but
adjust counters explicitly inside the same transaction, before the delete:

```ruby
Block.transaction do
  current_user.blocks_made.find_or_create_by(blocked: @target)
  follows = Follow.where(follower: [current_user, @target], followed: [current_user, @target])
  # delete_all skips Follow's callbacks (wanted for notifications, NOT for the
  # accepted-only counter caches) — apply the decrements explicitly, same transaction.
  follows.accepted.pluck(:follower_id, :followed_id).each do |follower_id, followed_id|
    User.update_counters(followed_id, followers_count: -1)
    User.update_counters(follower_id, following_count: -1)
  end
  follows.delete_all
end
```

(At most 2 rows — A→B and B→A — so the loop is O(1). Pending rows deleted here adjust nothing.)

**Specs.**

`spec/models/follow_counter_cache_spec.rb` (new) — define a local helper
`expect_counts_in_sync(*users)` asserting, per user,
`user.reload.followers_count == user.followers.count` **and**
`user.reload.following_count == user.following.count` (this is the spec-guarded **drift check**;
every example ends with it, so any silently-broken path fails loudly). Cover:
1. create accepted (public target) → +1/+1
2. create pending (private target) → 0/0
3. pending → `update!(status: :accepted)` → +1/+1
4. destroy pending (cancel/decline) → 0/0
5. destroy accepted (unfollow/remove) → −1/−1
6. defensive accepted→pending flip → −1/−1
7. rolled-back create inside a transaction → counts unchanged (proves the in-transaction
   callback choice)
8. `user.destroy` with follows in both directions → surviving counterpart's counts correct
   (dependent-destroy cascade routes through `after_destroy`)

`spec/models/follow_spec.rb` — `dismiss_request_notification!` destroys exactly the matching
`follow_request` notification and no others.

`spec/models/block_spec.rb` (or a new request example in `spec/requests/block_spec.rb`, whichever
file already exercises the follow-severing path) — blocking a mutual accepted-follow pair
decrements all four counts; blocking with only a pending row changes nothing; counts end in sync
via the same helper.

**Acceptance.**
- All counter-cache spec paths green; drift helper used in every example.
- Blocks controller comment rewritten to state the new contract (the old "no destroy callbacks"
  claim removed).
- Existing follow/block spec files still green; no other controller changed.

---

## Task 3 — Bulk private→public accept side effects (`AcceptPendingFollowsJob`) — gap 5

**Rationale.** `users_controller.rb:57`'s `passive_follows.pending.update_all(status: :accepted)`
skips notifications, badges, request-notification dismissal, and (since Task 2) counters. Routing
each row through `update!` makes *all* of those fire from the one place they already live — the
`Follow` model — instead of re-implementing them. A job absorbs large sets.

**Files.**
- Create `app/jobs/accept_pending_follows_job.rb`
- Edit `app/controllers/users_controller.rb` (the `update` action, ~lines 52–57 only)
- Create `spec/jobs/accept_pending_follows_job_spec.rb`
- Extend `spec/requests/private_visibility_spec.rb` (or wherever the existing
  private→public bulk-accept behaviour is pinned — find and update that assertion; the old
  "no notification blast" pin is superseded by this owner-approved design)

**Change — job** (pattern: `app/jobs/conclude_stale_debates_job.rb` — `find_each`, per-row
rescue+log so one bad row never wedges the batch):

```ruby
class AcceptPendingFollowsJob < ApplicationJob
  # Accept every pending follow request aimed at `user` (private→public flip).
  # Per-row update! (NOT update_all) on purpose: the Follow model's callbacks carry
  # ALL the accept side effects — follow_accepted to the requester, new_follower +
  # first_follower badge to the target, and the accepted-only counter caches.
  def perform(user)
    user.passive_follows.pending.find_each do |follow|
      follow.update!(status: :accepted)
      follow.dismiss_request_notification!
    rescue => e
      Rails.logger.error("AcceptPendingFollowsJob: failed to accept follow #{follow.id}: #{e.class}: #{e.message}")
    end
  end
end
```

**Change — `UsersController#update`.** Replace the `update_all` line with:

```ruby
if was_private && !@user.private?
  # Small sets accept inline (the flip's effects are immediately visible);
  # large sets go to the job so the request doesn't stall on N notification writes.
  if @user.passive_follows.pending.count <= AcceptPendingFollowsJob::INLINE_THRESHOLD
    AcceptPendingFollowsJob.perform_now(@user)
  else
    AcceptPendingFollowsJob.perform_later(@user)
  end
end
```

Define `INLINE_THRESHOLD = 25` on the job. Update the surrounding comment (the "no notification
blast" rationale is superseded — say why: accepting silently left requesters unaware they may now
follow, and left counters/badges unfired).

**Specs.**
- Job spec: given a user with N pending + M accepted passive follows — all pending become
  accepted; requesters each receive `follow_accepted`; target receives `new_follower` per row +
  `first_follower` badge once; every `follow_request` notification for those rows is destroyed;
  counts end in sync (reuse the drift assertion style from Task 2); a row that raises is logged
  and skipped while the rest proceed.
- Request spec: PATCH profile flipping private→false with ≤25 pending runs inline (effects
  visible in the response cycle); with >25 enqueues the job
  (`have_enqueued_job(AcceptPendingFollowsJob)`); flipping public→private enqueues nothing;
  a failed update (validation error) enqueues nothing.

**Acceptance.**
- `update_all(status: :accepted)` no longer exists anywhere in `app/`.
- All accept side effects verified per row; counts in sync after bulk flip.
- Existing private-visibility specs updated where they pinned the silent bulk accept.

---

## Task 4 — Stale-request expiry: `ExpireStaleFollowRequestsJob` — gap 6

**Rationale.** Pending requests currently live forever. 30-day expiry, silent to the requester
(matches decline's "no blast" convention). Pending rows never touched after create, so
`created_at` is the correct age signal.

**Files.**
- Create `app/jobs/expire_stale_follow_requests_job.rb`
- Edit `config/recurring.yml`
- Create `spec/jobs/expire_stale_follow_requests_job_spec.rb`

**Change — job** (same shape as `ConcludeStaleDebatesJob`):

```ruby
class ExpireStaleFollowRequestsJob < ApplicationJob
  # Expire follow requests that sat unanswered for 30+ days. destroy (not
  # delete_all) so Follow's callbacks run — a pending row adjusts no counters
  # (accepted-only guard), and destroying fires no notification. The requester is
  # deliberately NOT told (mirrors decline's no-blast convention); the target's
  # stale request card is dismissed.
  def perform
    Follow.pending.where(created_at: ...30.days.ago).find_each do |follow|
      follow.dismiss_request_notification!
      follow.destroy
    rescue => e
      Rails.logger.error("ExpireStaleFollowRequestsJob: failed to expire follow #{follow.id}: #{e.class}: #{e.message}")
    end
  end
end
```

**Change — `config/recurring.yml`** (production block, alongside `conclude_stale_debates`):

```yaml
  expire_stale_follow_requests:
    class: ExpireStaleFollowRequestsJob
    schedule: every day at 4am
```

(4am, not 3am — don't stack with the debate sweep.)

**Specs.** Job spec: a 31-day-old pending follow is destroyed and its `follow_request`
notification destroyed; a 29-day-old pending follow survives; an old **accepted** follow
survives untouched; **no** notification of any category is created for the requester; both
users' counter columns unchanged and in sync; a raising row is logged and skipped.

**Acceptance.** Job + schedule entry present; spec green; `recurring.yml` parses
(`bin/rails runner 'SolidQueue::RecurringTask'` boot or equivalent — a broken YAML here breaks
the worker, not the web app, so eyeball it against the existing entries).

---

## Task 5 — Pending-requests inbox (`follow_requests#index`) — gap 1

**Rationale.** Requests are currently manageable only from notification cards, which can be
deleted or buried. A standalone owner-only inbox, linked from the user dropdown with a count.

**Files.**
- Edit `config/routes.rb` (one route, next to the existing follow_requests routes at ~75–76)
- Edit `app/controllers/follow_requests_controller.rb` (add `index`)
- Create `app/views/follow_requests/index.html.erb`
- Create `app/views/follow_requests/_request_row.html.erb`
- Edit `app/views/shared/_navbar.html.erb` (one menu row in the `<details>` dropdown, ~line 88)
- Extend `spec/requests/follow_request_spec.rb`
- Create `spec/system/follow_requests_spec.rb`

**Change — route.** Above the existing `patch "/follow_requests/:id"` (route order is
irrelevant here — static segment vs `:id` — but keep the family together):

```ruby
# Pending follow-requests inbox (2026 follow gaps). Own-resource surface: no
# username in the URL — always the signed-in user's own pending passive follows
# (like /notifications, /blocks). MAIN route (CSRF on) — its rows carry the
# accept/decline button_to's.
get "/follow_requests", to: "follow_requests#index", as: :follow_requests
```

**Change — controller.** `index` must not run the existing `before_action :set_follow`
(`Follow.find(params[:id])` would raise) — scope it: `before_action :set_follow, except: [:index]`.

```ruby
# Own-resource inbox (like BlocksController#index): scoped to current_user by
# construction, so skip_authorization rather than a policy that restates it.
def index
  skip_authorization
  @follows = current_user.passive_follows.pending
    .includes(follower: {avatar_attachment: :blob}).order(created_at: :desc)
end
```

**Change — `index.html.erb`.** Same page skeleton as `users/followers.html.erb`: navbar,
`max-w-xl` main, `h1` "Follow requests", a `div id="follow_requests_list" class="flex flex-col shadow"`
wrapper; inside, `render partial: "request_row", collection: @follows, as: :follow` when any,
else `render "ui/empty_state", message: "No pending follow requests", icon: "user-plus"`.
The wrapper's `follow_requests_list` id is a stable Turbo target Task 6 relies on.

**Change — `_request_row.html.erb`.** Local: `follow`. Outer
`<div id="<%= dom_id(follow, :request) %>" class="flex items-center gap-3 p-3 bg-white border-b border-gray-100">`
(hairline colour matters — see `_user_row`'s currentColor note). Contents: the requester's
avatar via `render "ui/avatar", user: follow.follower, size: :row`, name + `@handle` block
linking to `profile_path(follow.follower.username)` (link wraps only the identity block, taking
`flex-1` — the action buttons must NOT nest inside an `<a>`), then Accept/Decline exactly as the
notification card does (`_notification_card.html.erb:166–169`):
`button_to "Accept", follow_request_path(follow), method: :patch, class: ds_button_classes(variant: :link)`
and `button_to "Decline", follow_request_path(follow), method: :delete, class: ds_button_classes(variant: :link, tone: "grey")`.
(This task keeps the existing `redirect_back` responses — from the inbox that returns to the
inbox, which works; Task 6 upgrades both surfaces to turbo_stream.)

**Change — navbar dropdown.** Insert one row between "Dashboard" and the moderation row
(`_navbar.html.erb` ~line 88), following the moderation row's count idiom (a menu row may state
a number in words; the bar itself keeps its dot-only rule):

```erb
<%= link_to follow_requests_path, class: ds_menu_item_classes do %>
  Follow requests
  <% pending = current_user.passive_follows.pending.count %>
  <% if pending > 0 %>
    <span id="nav-follow-requests-count" class="ml-1 text-xs text-grey">(<%= pending %>)</span>
  <% end %>
<% end %>
```

The `nav-follow-requests-count` id is a Task 6 turbo target — keep it. (Cost note for the
review: one indexed COUNT on `follows.followed_id` per signed-in navbar render, same class of
query as `unread_notifications_count` directly below it.)

**Specs.**
- Request (`spec/requests/follow_request_spec.rb`): signed-out GET `/follow_requests` redirects
  to login; owner sees only their **own pending** requests (another user's pending row and the
  owner's *accepted* follower both absent); empty state renders when none; rows carry
  accept/decline forms pointing at `follow_request_path`.
- System (`spec/system/follow_requests_spec.rb`, `js: true`): private user with 2 pending
  requests opens the dropdown, sees "Follow requests (2)", visits the inbox, accepts one and
  declines the other, ends at the empty state (post-Task-6 this happens without navigation;
  written now against the redirect flow, Task 6 adjusts if needed); requester of the accepted
  row now appears in the followers list.

**Acceptance.**
- Inbox owner-scoped by construction; `verify_authorized` satisfied via `skip_authorization`.
- Accept/decline from BOTH the inbox and the notification card still work.
- Dropdown shows the count only when > 0; no navbar-bar badge added.

---

## Task 6 — Turbo-ify Accept/Decline — gap 3

**Rationale.** `follow_requests#update`/`#destroy` currently `redirect_back` — a full page
reload from both the inbox and the notification card. Turbo-stream responses remove the acted-on
row/card in place. One response body serves both surfaces because `turbo_stream.remove` of an
absent target is a silent no-op.

**Files.**
- Edit `app/controllers/follow_requests_controller.rb`
- Create `app/views/follow_requests/update.turbo_stream.erb`
- Create `app/views/follow_requests/destroy.turbo_stream.erb`
- Create `app/views/follow_requests/_actioned.turbo_stream.erb` (shared streams — see below)
- Extend `spec/requests/follow_request_spec.rb`
- Extend `spec/system/follow_requests_spec.rb` and `spec/system/notifications_spec.rb`

**Change — controller.** In both actions, capture what the streams need **before** destruction,
then respond in both formats (HTML fallback keeps `redirect_back` for no-JS):

```ruby
def update
  authorize @follow, :update?, policy_class: FollowRequestPolicy
  @follow.update!(status: :accepted)
  @dismissed_notification_ids = @follow.dismiss_request_notification!.map(&:id)
  respond_to do |f|
    f.turbo_stream
    f.html { redirect_back fallback_location: notifications_path, status: :see_other }
  end
end
```

`destroy` mirrors it (`@follow.destroy` after capturing ids — dismiss first, then destroy; order
is safe either way since dismissal queries by user-id pair, not follow id). Note
`dismiss_request_notification!` already returns the destroyed rows (`destroy_all` returns the
array) — Task 2 wrote its comment promising exactly this use.

**Change — streams.** Both `update.turbo_stream.erb` and `destroy.turbo_stream.erb` render the
same shared partial `_actioned.turbo_stream.erb` (accept and decline have identical DOM
consequences — the row/cards disappear):

```erb
<%# Remove this request everywhere it renders. Absent targets are no-ops, so one
    body serves both the inbox and the notifications page. %>
<%= turbo_stream.remove dom_id(@follow, :request) %>
<% @dismissed_notification_ids.each do |id| %>
  <%= turbo_stream.remove "notification_#{id}" %>
<% end %>
<%# Refresh the dropdown count (id from _navbar; absent when the menu isn't rendered → no-op). %>
<% remaining = current_user.passive_follows.pending.count %>
<% if remaining.zero? %>
  <%= turbo_stream.remove "nav-follow-requests-count" %>
  <%# Last request actioned: swap the inbox list for its empty state (no-op elsewhere). %>
  <%= turbo_stream.update "follow_requests_list" do %>
    <%= render "ui/empty_state", message: "No pending follow requests", icon: "user-plus" %>
  <% end %>
<% else %>
  <%= turbo_stream.update "nav-follow-requests-count", "(#{remaining})" %>
<% end %>
```

(Verify the notification card's DOM id prefix: `_notification_card` wraps in
`dom_id(notification)` → `notification_<id>` — confirm against the partial's actual wrapper
before hardcoding the string, or build with `ActionView::RecordIdentifier.dom_id`.)

**Specs.**
- Request: PATCH/DELETE with `Accept: text/vnd.turbo-stream.html` returns turbo-stream removing
  `follow_<id>_request` and the notification target; plain HTML form post still 303s
  (`redirect_back`). Non-target user still 403s (regression pin).
- System: inbox accept/decline removes the row **without navigation** and shows the empty state
  after the last one; notification-card Accept removes the card in place; dropdown count
  updates/disappears.

**Acceptance.** Both surfaces act in place; HTML fallback intact; policies untouched;
`notifications_spec.rb` system flow still green.

---

## Task 7 — Remove-follower — gap 2

**Rationale.** A user can currently only escape an unwanted follower by blocking. Standard
social-platform affordance: the followed user silently removes the accepted follow.

**Files.**
- Edit `config/routes.rb` (one route, with the follow family at ~66–67)
- Edit `app/controllers/follows_controller.rb` (add `remove_follower`)
- Edit `app/policies/follow_policy.rb` (add `remove_follower?`)
- Edit `app/views/users/_user_row.html.erb` (optional `remove_path:` local)
- Edit `app/views/users/followers.html.erb` (pass the local when owner)
- Create `app/views/follows/remove_follower.turbo_stream.erb`
- Extend `spec/requests/follow_spec.rb`, `spec/system/follow_spec.rb`

**Change — route.**

```ruby
# Remove a follower (2026 follow gaps): the FOLLOWED user severs an accepted
# follow pointed at them. :username is the FOLLOWER being removed — the mirror
# image of DELETE /u/:username/follow, where :username is the followed target.
delete "/u/:username/follower", to: "follows#remove_follower", as: :remove_follower
```

**Change — policy.** In `FollowPolicy`:

```ruby
# Only the followed user may remove a follower (the mirror of destroy?, which is
# follower-only). record is the accepted Follow row being severed.
def remove_follower? = user.present? && record.followed_id == user.id
```

**Change — controller.** Mirrors `destroy`'s authorize/skip pattern (idempotent when no row):

```ruby
# Sever an accepted follow pointed at me. @target (set_target, :username) is the
# FOLLOWER being removed. Scoped .accepted: a pending request is not a follower —
# it is declined via follow_requests#destroy, and removing it here would skip the
# request-notification dismissal that path owns.
def remove_follower
  @follow = current_user.passive_follows.accepted.find_by(follower: @target)
  authorize @follow, :remove_follower? if @follow
  skip_authorization if @follow.nil?
  @follow&.destroy   # accepted → Task 2's after_destroy decrements both counters
  respond_to do |f|
    f.turbo_stream
    f.html { redirect_to user_followers_path(current_user.username), status: :see_other }
  end
end
```

(`current_user.passive_follows` already pins `followed_id == current_user.id`, so the policy is
belt-and-braces — keep both; that is the house style in `follows#destroy`.)

**Change — `_user_row.html.erb`.** Add an optional local,
`remove_path = local_assigns[:remove_path]` (default nil → **byte-identical rendering to today**
for the followers/following/blocks callers that pass nothing). When present, the row's outer
element becomes a `<div id="<%= dom_id(user, :follower_row) %>" class="flex items-center gap-3 p-3 bg-white border-b border-gray-100">`
with the existing avatar+name block inside the profile `link_to` (link takes `flex-1`, drops the
border/padding it no longer owns, keeps `hover:bg-gray-50` on the row div), plus a trailing
`button_to "Remove", remove_path, method: :delete,` `form: {data: {turbo_confirm: "Remove @#{user.username} from your followers?"}},`
thin-outline pill styling copied from `_follow_button`'s `:card` `outline_classes` literal
(`px-4 py-1 text-sm rounded-full border border-primary text-primary bg-card`). The button must
be a sibling of the `<a>`, never nested in it (invalid HTML). Update the partial's header
comment (it documents its callers).

**Change — `followers.html.erb`.** Pass the local only on the owner's own page:

```erb
<%= render partial: "user_row", collection: @users, as: :user,
      locals: {owner: current_user == @user} %>
```

— concretely: `remove_path: (current_user == @user ? remove_follower_path(user.username) : nil)`
via `locals`. Since `remove_path` is per-row, compute the owner boolean once in the view and
have `_user_row` build the path itself from an `removable:` boolean if that reads cleaner —
implementer's choice; the acceptance criterion is: **Remove renders on every row of my own
followers page and nowhere else** (not on someone else's followers page, not on following, not
on blocks).

**Change — `remove_follower.turbo_stream.erb`.**

```erb
<%# Remove the row on my followers list; refresh my follower-count chip if one is
    on the page (profile header — absent target is a no-op). %>
<%= turbo_stream.remove dom_id(@target, :follower_row) %>
<%= turbo_stream.replace dom_id(current_user, :follower_count) do %>
  <%= render "users/follower_count", user: current_user %>
<% end %>
```

**Specs.**
- Request (`spec/requests/follow_spec.rb`): followed user DELETEs
  `/u/:follower/follower` → follow gone, both counters decremented and in sync; a third party
  (someone the follower doesn't follow… i.e. any user who is not the followed) gets no-op/403 —
  concretely: the **follower themselves** cannot use this route to sever rows pointed at others
  (they'd find nothing: `current_user.passive_follows` scoping); repeat DELETE is idempotent
  200/303, not 500; a **pending** requester is NOT removable via this route (row survives);
  signed-out → login redirect.
- System (`spec/system/follow_spec.rb`, `js: true`): owner sees Remove on own followers page,
  `accept_confirm { click_button "Remove" }` removes the row in place; visiting another user's
  followers page shows no Remove control.

**Acceptance.** Route/policy/action/view wired as above; `_user_row` default rendering unchanged
(diff the other two callers' rendered HTML in specs or by eyeball); counters stay in sync
(callbacks, verified by the request spec).

---

## Task 8 — Follows polish: cancel-pending dismissal + unfollow confirm — gaps 4 & 7

**Rationale.** Two small `FollowsController`/`_follow_button` fixes. (4) Cancelling a pending
request leaves the target's "requested to follow you" card offering dead buttons — dismiss it.
(7) One accidental click on "Following" silently severs a relationship — add a confirm; the
"Requested"/cancel path stays confirm-free (cancelling a request is low-stakes and reversible).

**Files.**
- Edit `app/controllers/follows_controller.rb` (`destroy` only)
- Edit `app/views/users/_follow_button.html.erb` (the "Following" `button_to` only)
- Extend `spec/requests/follow_spec.rb`, `spec/system/follow_spec.rb` (or `private_spec.rb`
  where cancel-request is already exercised)

**Change — `follows#destroy`.** Before `@follow&.destroy`:

```ruby
# A cancelled REQUEST must clear the target's follow_request card (the same
# dismissal accept/decline perform) — otherwise it offers dead buttons forever.
# An unfollow of an accepted row has no such card, so this is pending-only.
@follow.dismiss_request_notification! if @follow&.pending?
```

**Change — `_follow_button.html.erb`.** On the "Following" branch's `button_to` (line ~92) only:

```erb
form: {data: {turbo_confirm: "Unfollow @#{user.username}?"}},
```

The "Requested" branch (line ~100) — which reuses the same route — gets **no** confirm; add one
ERB comment line saying so (and why), since the FROZEN header comment stresses the route reuse.
Update that header's FROZEN paragraph to note the confirm is part of the accepted-state button.

**Specs.**
- Request: DELETE unfollow-route on a **pending** row destroys the target's `follow_request`
  notification; on an **accepted** row destroys no notifications; both leave counters in sync
  (pending: unchanged; accepted: −1/−1 — already covered by Task 2's model spec, assert at the
  request level once).
- System (`js: true`): clicking "Following" pops a confirm — `dismiss_confirm` leaves the follow
  intact, `accept_confirm` flips the button to "Follow" and drops the count; clicking
  "Requested" cancels immediately with **no** dialog (Cuprite would raise on an unexpected
  modal-wait; assert the button flips without `accept_confirm`).

**Acceptance.** Confirm on accepted-unfollow only; pending-cancel clears the request card;
no other `_follow_button` branch changed (blocked/unblock/block buttons untouched).

---

## Task 9 — Read flip to counter columns + final gate — rest of gap 8

**Rationale.** All mutation paths are now callback- or explicitly-synced and have baked under
the Task 2 drift spec through Tasks 3–8. Point every count read at the columns; this is also
what Slice B's hovercard will read (`followers_count`/`following_count` — note it in the
partial comment so B's implementer finds it).

**Files.**
- Edit `app/views/users/_follower_count.html.erb` (line 6: `user.followers.size` →
  `user.followers_count`; rewrite the header comment — the "no denormalized column this slice"
  note is now false)
- Edit `app/views/users/_profile_header.html.erb` (~line 133 followers chip is the
  `_follower_count` partial or an inline `.size` — flip whichever it is; line 138:
  `user.following.size` → `user.following_count`)
- Edit `app/views/users/_gated_header.html.erb` (~lines 35, 39: same two flips)
- Edit `app/controllers/analytics_controller.rb` (line 18:
  `current_user.followers.count` → `current_user.followers_count`; keep/update the surrounding
  comment about the analytics query object)
- Extend `spec/requests/profile_spec.rb`, `spec/requests/analytics_spec.rb`

**Change.** Pure read-source swaps, no markup changes. Grep first —
`grep -rn "followers\.\(size\|count\)\|following\.\(size\|count\)" app/` — and flip every
rendering read; **do not** flip semantic membership checks
(`current_user.following.include?`, `passive_follows.accepted.exists?`, `visible_to?` /
`accepted_follower?`, `User.visible_to`'s `following_ids` subquery) — those are relationship
queries, not count displays, and must stay live.

**Specs.**
- `spec/requests/profile_spec.rb`: profile (and gated profile) render counts that match a
  just-mutated state — follow a user, assert the profile header shows the incremented number
  (this now proves column-read + callback-write end to end).
- `spec/requests/analytics_spec.rb`: dashboard follower stat equals `followers_count` and
  equals the live `followers.count` (one more drift pin at the surface level).

**Final gate (the whole slice).** After this task's targeted specs are green:

```bash
bin/ci
```

— the definition of record for green (StandardRB, Brakeman, bundler-audit, db:test:prepare,
Tailwind build, full suite incl. system specs). Run it **alone** (shared test DB — no concurrent
suites; see the CI gotchas memo re orphaned processes holding `hoojah_test`). Then
`grep -c 'N+1 queries detected' log/prosopite.log` and compare against the pre-slice baseline
(146 as of Slice 10) — investigate meaningful growth, but prosopite stays log-only.

**Acceptance.**
- No rendering surface computes a follow count from the association; membership/visibility
  checks untouched.
- `bin/ci` fully green; Brakeman and bundler-audit clean; no unexplained prosopite growth.

---

## Counter-cache invariant checklist (gap 8 — audit this before calling the slice done)

Definitions: `F = follow.follower` (the actor who follows), `T = follow.followed` (the target).
Invariant at all times, both columns, every user:
`u.followers_count == u.passive_follows.accepted.count` and
`u.following_count == u.active_follows.accepted.count`.

| # | Mutation path | Entry point | Mechanism | Delta |
|---|---|---|---|---|
| 1 | Follow a public user (create accepted) | `follows#create` | `after_create` (accepted guard) | T.followers +1, F.following +1 |
| 2 | Request a private user (create pending) | `follows#create` | guard skips | none |
| 3 | Re-follow while already following/requested | `follows#create` (`find_or_initialize_by` no-op save) | no INSERT/UPDATE | none |
| 4 | Double-click race (`RecordNotUnique`, rollback) | `follows#create` rescue | `after_create` is in-transaction → rolled back | none |
| 5 | Accept a request (pending→accepted) | `follow_requests#update` | `after_update` on `saved_change_to_status?` | T.followers +1, F.following +1 |
| 6 | Decline a request (destroy pending) | `follow_requests#destroy` | `after_destroy` guard skips | none |
| 7 | Cancel own request (destroy pending) | `follows#destroy` | `after_destroy` guard skips | none |
| 8 | Unfollow (destroy accepted) | `follows#destroy` | `after_destroy` | T.followers −1, F.following −1 |
| 9 | Remove follower (destroy accepted) | `follows#remove_follower` (Task 7) | `after_destroy` | T(=current_user).followers −1, F.following −1 |
| 10 | Block severs follows (**`delete_all` — callbacks skipped**) | `blocks#create` (Task 2) | **explicit `User.update_counters` in the same transaction, accepted rows only** | per accepted row deleted: its T.followers −1, its F.following −1 (≤2 rows) |
| 11 | Private→public bulk accept | `users#update` → `AcceptPendingFollowsJob` (Task 3) | per-row `update!` → path 5's callback | per row: +1/+1 |
| 12 | Stale-request expiry (destroy pending) | `ExpireStaleFollowRequestsJob` (Task 4) | `after_destroy` guard skips | none |
| 13 | User deletion cascade (`dependent: :destroy` on active/passive follows) | `user.destroy` | per-row `after_destroy` | surviving counterpart −1 on the relevant column per accepted row; deleted user's own columns are moot |
| 14 | Defensive accepted→pending (no app path; console/future code) | any `update!` | `after_update` symmetric branch | T.followers −1, F.following −1 |

Standing rules the implementers and reviewers must hold:
- **Counter callbacks are in-transaction** (`after_create`/`after_update`/`after_destroy`) —
  never `_commit`; a rolled-back write must roll back its deltas (path 4 is the proof case).
  Notification/badge callbacks stay on `_commit` — do not unify them.
- **Any new `delete_all`/`update_all`/`insert_all` touching `follows` must ship its own explicit
  adjustment in the same transaction** — the `Follow` model header comment (Task 2) states this;
  reviewers grep for those methods on every task in this slice and beyond.
- **`User.update_counters` only** (atomic SQL, no validations/callbacks/races) — never
  `increment!`/`save`.
- **The drift spec is the tripwire**: `spec/models/follow_counter_cache_spec.rb`'s
  `expect_counts_in_sync` closes every example; any task adding a follow-mutation spec should
  end its examples with the same comparison (columns vs live accepted-only scopes).
- **No clamping**: never floor the columns at zero in app code — a negative count is a bug
  surfacing, and clamping would hide it from the drift spec.

## Per-task review checklist (reviewer runs after every task)

1. Task's named specs green; StandardRB clean on touched files.
2. Every new/changed non-Devise action: exactly one `authorize`/`skip_authorization`.
3. New routes are main routes with a why-comment, matching the file's house style; no
   `resources`; records addressed by `:username`/`:id`-of-Follow only.
4. Any touched `follows` bulk-write audited against the invariant table above.
5. Comments kept current — this codebase carries the *why* at unusual density; a change that
   falsifies a comment (e.g. blocks_controller's "no destroy callbacks", `_follower_count`'s
   "no denormalized column") must rewrite it.
6. No concrete Tailwind class introduced in ERB comments; no interpolated classes without a
   safelist entry (none expected this slice).
7. Commit: plain imperative subject, no branding, no amend of others' commits.
