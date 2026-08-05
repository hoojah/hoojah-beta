# Slice 3: Social Foundation — Follow + Following Feed + @mentions

_Design spec. Date: 2026-08-05. Status: **design + specialist-reviewed** (security, simplicity — folded, v2).
Part of the "land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`)._

> **Review incorporation (v2):** **Critical** — `format_body` must tokenize mentions on RAW text before
> `simple_format`/`auto_link`, then substitute the anchor after (the original gsub-over-rendered-HTML would
> corrupt markup when a body contains an email/`@`-URL). Mention parsing is **inline** in
> `after_create_commit` (no job — matches every existing notification callback), **create-only**, and
> **idempotent via an existence check**. `MENTION_RE` gets a `(?<!\w)` lookbehind. Following feed uses
> `following_ids + [user.id]` (not raw SQL). Fixed the `FollowPolicy` authorize call (was ambiguously
> `UserPolicy#follow?`). Guard anonymous `?filter=following` (fall back to global, no 500). Added a
> follow/unfollow rack-attack throttle + graceful `RecordNotUnique` on double-follow.

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
| Mention parsing | **Inline** `after_create_commit`, **create-only**, cap 10 unique/hoojah, idempotent existence-check (no job, no edit-diff) |
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
`FollowsController` (`authenticate_user!`): `create` does
`authorize Follow.new(follower: current_user, followed: @target), :create?` then
`current_user.active_follows.find_or_create_by(followed: @target)` (`find_or_create_by` + a
`rescue ActiveRecord::RecordNotUnique` make a concurrent double-click an idempotent no-op, not a 500);
`destroy` loads the `@follow`, `authorize @follow, :destroy?`, removes it. Both respond with a
`turbo_stream.replace dom_id(@target, :follow_button)` (flips Follow↔Following) + replace the
`dom_id(@target, :follower_count)` chip. `button_to`, no Stimulus. **rack-attack:** add a
`throttle("follow/user", limit: 20, period: 1.minute)` keyed on the warden user for
`POST/DELETE /u/:username/follow` (no throttle today → follow/unfollow cycling would spam `new_follower`).
**Build note:** these routes/controller live in the main `routes.rb`/`app/controllers` (NOT `Api::V1`,
whose `null_session` disables CSRF); `button_to` carries the authenticity token.

### 4. Following feed (a scope on the existing feed)

`Hujah` scope (use the association's `_ids`, not raw SQL — leaner + slots the future Block filter in as
plain Ruby `following_ids - blocked_ids`):
```ruby
scope :timeline_for, ->(user) {
  where(parent_id: nil).where(user_id: user.following_ids + [user.id])
}
```
`HujahsController#index` branches on `params[:filter]`: `"following"` **only when `user_signed_in?`** →
`Hujah.timeline_for(current_user)`; otherwise (anonymous, or no filter) the existing global
`Hujah.where(parent_id: nil)`. This guard is a **must-fix** — without it an anonymous `?filter=following`
calls `current_user.id` on nil → 500; the graceful fallback is the global feed. Everything downstream
(pagy `:countless`, append to `#hujah-feed`, `_load_more`) is unchanged — **`_load_more` must carry the
`filter` param**. "Everyone | Following" tabs are server-rendered links (`root_path` vs
`root_path(filter: "following")`); the Following tab shows only for signed-in users. Empty state when
following nobody. Not a client filter — does **not** reuse `response_filter_controller`.

### 5. Authorization (Pundit)

`FollowPolicy#create? = user.present?` (controller forces `follower = current_user`, like `FlagsController`);
`destroy? = record.follower_id == user.id`. The controller calls `FollowPolicy` explicitly
(`authorize Follow.new(...), :create?` / `authorize @follow, :destroy?`) — **not** `UserPolicy#follow?`
(which doesn't exist and would 500 under `verify_authorized`). Follows are public → `UsersController#followers`
and `#following` **must each call `skip_authorization`** (or they 500); the feed `index` already
`skip_authorization`s. Per-action wiring per Slice 2 discipline. No `policy_scope` on public follow lists.

### 6. @mentions

`MENTION_RE = /(?<!\w)@([a-zA-Z0-9_]+)/` — the `(?<!\w)` lookbehind means an `@` preceded by a word char
(i.e. inside an email like `foo@bar`) is NOT a mention, sidestepping the auto_link/email ordering hazard.

- **Notify — inline, create-only, idempotent** (matches every existing notification callback —
  `notify_parent_owner`, `cast_vote`, `Follow#notify_followed`; the work is capped at 10, cheaper than
  `cast_vote`'s inline work, so no job):
  ```ruby
  after_create_commit :notify_mentions   # create only — edit-mention handling deferred with the edit UI

  def notify_mentions
    handles = body.scan(MENTION_RE).flatten.uniq.first(10)   # cap = anti-spam, dedup
    User.where(username: handles).where.not(id: user_id).each do |u|
      next if Notification.exists?(user: u, hujah_id: id, category: :mention, subject_user_id: user_id)
      Notification.create!(user: u, category: :mention, hujah_id: id, subject_user_id: user_id)
    end
  end
  ```
  The `exists?` guard makes it "notify at most once per (hoojah, mentioner, mentioned)" — robust to any
  future edit churn without body-diffing. Unknown handles silently ignored; no self-notify.
  (Cross-hoojah repeat-mention of one victim is bounded only by the `compose/user` throttle — a known
  harassment gap deferred to the Block/mute Safety slice; noted, not silently assumed away.)
- **Render — tokenize BEFORE formatting (CRITICAL).** Never `gsub` mentions over already-rendered HTML
  (that would match an `@` inside an `auto_link`-generated `href="mailto:…"`/URL and splice an unescaped
  `"`, corrupting markup). Extract mentions from the RAW body into placeholder tokens first, run
  `simple_format` + `auto_link`, then swap the placeholders for the anchors:
  ```ruby
  def format_body(text)
    handles = []
    tokenized = text.to_s.gsub(MENTION_RE) { handles << $1; "\uE000#{handles.size - 1}\uE001" }
    linked = auto_link(simple_format(tokenized), html: { target: "_blank", rel: "noopener" })
    linked.gsub(/\uE000(\d+)\uE001/) do
      h = handles[$1.to_i]
      %(<a href="/u/#{ERB::Util.url_encode(h)}" class="text-primary">@#{ERB::Util.html_escape(h)}</a>)
    end.html_safe
  end
  ```
  (`\uE000`/`\uE001` are Unicode private-use markers — can't appear in user text or be produced by
  autolinking. `ERB::Util` escaping is redundant under the current charset but is cheap defense-in-depth
  if the capture is ever loosened.) Linkify optimistically (no existence query → no feed N+1; a dead
  handle 404s — acceptable).

## Gem manifest

**None.** Follow/mention/feed reuse existing infra (Solid Queue, Notification, Turbo, Pundit).

## Component boundaries

- `Follow` model (validations + `notify_followed`); `User` follow associations; `Hujah#timeline_for` scope
  + `MENTION_RE` + `notify_mentions` (inline `after_create_commit`, no job).
- `FollowsController` (create/destroy, thin, `find_or_create_by` + `RecordNotUnique` rescue);
  `UsersController#followers/#following`; `HujahsController#index` gains the signed-in `filter` branch.
- `FollowPolicy`.
- Partials: `_follow_button`, `_follower_count`, feed `_feed_tabs`, `users/{followers,following}` lists;
  extend `_notification_card` (2 new categories); extend `format_body` (tokenized mention rendering).
- rack-attack: `follow/user` throttle. No new Stimulus. No new gems, no jobs.

## Testing

- **Model:** `Follow` (self-follow rejected at validation AND DB check, uniqueness, `new_follower`
  notification); `Hujah#timeline_for` (own + followed, excludes non-followed); `Hujah#notify_mentions`
  (notifies existing mentioned users once, caps at 10, skips self + unknown handles, idempotent via the
  `exists?` guard — a second identical create/callback makes no duplicate).
- **`format_body` injection safety (must-cover):** a body containing an **email** (`ping foo@bar.com`) and
  a **`@`-bearing URL** (`https://medium.com/@someuser`) must render with the mailto/URL anchor **intact**
  (no truncated `href`, no spliced `"`), the email/URL `@` NOT turned into a profile link, and a real
  `@handle` correctly linked to `/u/handle`; a body like `@evil"><script>` produces no live tag.
- **Request:** follow/unfollow Turbo-Stream (button + count flip; unauth → login; double-follow is an
  idempotent no-op, not 500); following feed (`?filter=following` returns own + followed only when signed
  in, **falls back to the global feed for anonymous — no 500**; load-more carries the filter); followers/
  following lists (`skip_authorization`, public); `FollowPolicy` (unauth create → 401, non-owner destroy →
  403); rack-attack `follow/user` throttle fires.
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
