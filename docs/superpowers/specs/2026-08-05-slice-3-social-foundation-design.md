# Slice 3: Social Foundation — Follow + Following Feed + @mentions

_Design spec. Date: 2026-08-05. Status: **design (from roadmap sketch)**, pending specialist review +
plan. Part of the "land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`)._

## Context

Slices 1–2 (merged `afeb5ad`) shipped the Hotwire foundation, Devise 5.0.4, Pundit, the feed + voting +
threaded arguments + compose/profile/notifications/flags/share. This slice adds the **social substrate**
that later features depend on (analytics follower-growth, badges, trending, debate reach). It is the
**foundation** slice of the social feature area; Badges, Trending, and Block/mute are their own later
slices.

## Goals

1. **Follow / unfollow** a user (public), with follower/following lists + counts on the profile.
2. **Following feed** — a personalized timeline (your own posts + posts from people you follow) toggled
   against the existing global "Everyone" feed.
3. **@mentions** — `@username` in a hoojah body links to the profile and notifies the mentioned user.

## Non-goals (later slices / deferred)

Badges, Trending, Block/mute + private accounts, bookmarks. Reactions beyond the 3-option vote (the vote
*is* the reaction primitive). Denormalized follower counts (compute on the profile page for MVP; add
columns only when a count appears in the feed).

## Locked decisions (defaults chosen; flagged for review)

| Decision | Choice |
|---|---|
| Follow visibility | **Public** (matches today's fully-public app); private accounts deferred |
| Follower counts | **Computed** (`.followers.size` on the profile page) — no denormalized columns yet |
| Following feed contents | **Your own posts + followed users' top-level hoojahs** (a home timeline) |
| Mention parsing | **Async** (Solid Queue job); no-notify-on-edit (diff added handles); cap 10 unique/hoojah |
| Block/mute | **Seam designed, not built** — the feed/mention/notification queries are written so a `Block` filter slots in later |

## Architecture

### 1. Follow model

```
follows
  follower_id  bigint  null: false  → users
  followed_id  bigint  null: false  → users
  timestamps
indexes:  unique [follower_id, followed_id];  [followed_id]
DB check: follower_id <> followed_id
```

```ruby
class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"
  validates :followed_id, uniqueness: { scope: :follower_id }
  validate :not_self
  after_create_commit :notify_followed

  private
  def not_self
    errors.add(:followed_id, "can't follow yourself") if follower_id == followed_id
  end
  def notify_followed
    Notification.create!(user_id: followed_id, category: :new_follower, subject_user_id: follower_id)
  end
end
```

`User` associations (mirror the existing `has_many` style): `active_follows`/`following` (through
follower_id), `passive_follows`/`followers` (through followed_id), both `dependent: :destroy`.

### 2. Notification enum — append-only (never renumber)

```ruby
enum :category, { admin: 0, announcement: 1, flag: 2, new_hoojah_response: 3, new_vote: 4,
                  mention: 5, new_follower: 6 }
```
`new_follower` links to `/u/:subject_user.username`; `mention` links to the hoojah. (These are the only
two categories this slice adds; `debate_*`/`badge_earned` come in their own slices.) Add
`belongs_to :subject_user` already exists (Slice 2). Notification cards get a `case` branch + Lucide icon
(`mention`→`at-sign`, `new_follower`→`user-plus`).

### 3. Follow controller + routes (Turbo)

```ruby
post   "/u/:username/follow",   to: "follows#create",  as: :follow_user
delete "/u/:username/follow",   to: "follows#destroy", as: :unfollow_user
get    "/u/:username/followers", to: "users#followers"
get    "/u/:username/following", to: "users#following"
```
`FollowsController` (`authenticate_user!`): `create` builds `current_user.active_follows.create(followed: target)`,
`destroy` removes it. Under Pundit: `authorize @target_user, :follow?` (or a `Follow` policy — see §5).
Both respond with a `turbo_stream.replace dom_id(target, :follow_button)` (flips Follow↔Following); the
profile follower-count chip is `dom_id(target, :follower_count)` and is replaced too. `button_to`, no
Stimulus.

### 4. Following feed (a scope on the existing feed)

`Hujah` scope:
```ruby
scope :timeline_for, ->(user) {
  where(parent_id: nil)
    .where("user_id = :me OR user_id IN (SELECT followed_id FROM follows WHERE follower_id = :me)", me: user.id)
}
```
(subquery, not a big `IN` array — no N+1.) `HujahsController#index` branches the base relation on
`params[:filter]`: `"following"` (signed-in only) → `Hujah.timeline_for(current_user)`; else the existing
global `Hujah.where(parent_id: nil)`. Everything downstream (pagy `:countless`, append to `#hujah-feed`,
`_load_more`) is unchanged — **`_load_more` must carry the `filter` param**. "Everyone | Following" tabs
are server-rendered links (`root_path` vs `root_path(filter: "following")`). Empty state when following
nobody. This is navigation (different data), so it does **not** reuse the client-side
`response_filter_controller`.

### 5. Authorization (Pundit)

`FollowPolicy#create? = user.present?` (controller forces `follower = current_user`, like `FlagsController`);
`destroy? = record.follower_id == user.id`. Follows are public → the profile follower/following lists +
the follow button use `skip_authorization` on the read actions; the feed `index` already
`skip_authorization`s. Per-action wiring per Slice 2 discipline (`verify_authorized` is app-wide). No
`policy_scope` needed on public follow lists.

### 6. @mentions

- **Parse** on `Hujah` body with the exact username charset:
  ```ruby
  MENTION_RE = /@([a-zA-Z0-9_]+)/
  after_create_commit :enqueue_mention_notifications
  after_update_commit :enqueue_mention_notifications, if: :saved_change_to_body?
  ```
  The callback **enqueues** `MentionNotificationJob(hujah_id, author_id, previous_body)`; the job does the
  N lookups + inserts off the request path (Solid Queue). On update, only newly-added handles
  (diff current vs `previous_body`) are notified — **never re-notify on every edit**.
- **Job:** `handles = body.scan(MENTION_RE).flatten.uniq.first(10)` (cap = anti-spam);
  `User.where(username: handles).where.not(id: author_id).find_each { |u| Notification.create!(user: u,
  category: :mention, hujah_id:, subject_user_id: author_id) }`. Unknown handles silently ignored; no
  self-notify; capped at 10 unique. (rack-attack's existing `compose/user` 20/min throttle bounds the
  outer rate.)
- **Render:** extend `format_body` to linkify handles **safely**. `simple_format` already sanitizes/escapes
  the user text; the mention gsub runs on that safe output, and because the capture is constrained to
  `[a-zA-Z0-9_]` no HTML metacharacter can reach the generated `href`/anchor, so re-marking `html_safe`
  is injection-safe:
  ```ruby
  def format_body(text)
    linked = auto_link(simple_format(text), html: { target: "_blank", rel: "noopener" })
    linked.gsub(MENTION_RE) { %(<a href="/u/#{$1}" class="text-primary">@#{$1}</a>) }.html_safe
  end
  ```
  Linkify optimistically (no existence query → no N+1 across the feed; a dead handle 404s — acceptable).
  Verify `auto_link` ordering doesn't consume a bare `@handle` as an email (it won't).

## Gem manifest

**None.** Follow/mention/feed reuse existing infra (Solid Queue, Notification, Turbo, Pundit).

## Component boundaries

- `Follow` model (validations + `notify_followed`); `User` follow associations; `Hujah#timeline_for` scope
  + `MENTION_RE` + mention-enqueue callbacks.
- `FollowsController` (create/destroy, thin); `UsersController#followers/#following`; `HujahsController#index`
  gains the `filter` branch.
- `FollowPolicy`.
- `MentionNotificationJob` (Solid Queue).
- Partials: `_follow_button`, `_follower_count`, feed `_feed_tabs`, `users/{followers,following}` lists;
  extend `_notification_card` (2 new categories); extend `format_body`.
- No new Stimulus.

## Testing

- **Model:** `Follow` (self-follow rejected, uniqueness, `new_follower` notification); `Hujah#timeline_for`
  (returns own + followed, excludes non-followed); `format_body` mention linkify + **injection safety**
  (a body like `@evil"><script>` produces no live tag).
- **Request:** follow/unfollow Turbo-Stream (button + count flip; unauth → login); following feed
  (`?filter=following` returns own + followed only; requires login; load-more carries the filter);
  followers/following lists; a non-owner can follow (public); `FollowPolicy` (unauth create → 401,
  non-owner destroy → 403).
- **Job:** `MentionNotificationJob` notifies existing mentioned users once, caps at 10, skips self +
  unknown handles; no re-notify when body unchanged / on edit only new handles.
- **System (cuprite):** follow button flips + count updates without reload; Following tab shows the
  timeline; a mention renders as a profile link.
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean. Eager-load to avoid feed N+1.

## Execution model

Spec → **3 specialist reviews (security/Stimulus/simplicity)** → `writing-plans` → subagent-driven build
with per-phase review gates. Build/test commands per `HANDOVER.md`.

## Risks / open questions

- **Public vs private follows** — MVP public; private accounts (request→approve via a `Follow.status`) is a
  later slice; keep `Follow` as the natural home for a `status` column.
- **Block/mute** is a real prerequisite for safe social — design the feed/mention/notification queries so a
  `Block(blocker, blocked)` filter (both directions; deletes reciprocal follow) slots in without a rewrite.
  Built in the Safety slice.
- **Mention spam / notification fatigue** — categories grow 4→6; caps + no-edit-renotify + rack-attack
  help; consider digest/grouping before volume climbs.
- **`updated_at` ordering** — voting bumps `updated_at`, so the following feed resurfaces voted hoojahs;
  confirm that's desired (default: yes, matches the existing feed).
- **Counter drift** — avoided in MVP by computing counts (no denormalized columns yet).

## Deferred to later program slices

Badges (+ `debate_won`), Trending sidebar, Block/mute + private accounts, bookmarks; the roadmap's Debate,
Analytics, and Privacy-hardening slices.
