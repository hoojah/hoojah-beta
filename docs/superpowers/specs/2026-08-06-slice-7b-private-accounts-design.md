# Slice 7b: Private Accounts

_Design spec. Date: 2026-08-06. Status: **design + specialist-reviewed** (security, simplicity — folded,
v2). "Land everything" program. Highest-blast-radius visibility change._

> **Review incorporation (v2).** Security found three leaks the v1 spec missed — **all folded as must-fix**:
> concluded **debate transcripts** (D-1), **notification bodies** rendering private content (N-1), and the
> **followers/following list pages** (L-1); plus **trending-cache staleness on the privacy flip** (T-1),
> the **`Api::V1` no-auth bypass** (A-1 — gated now because private is a *hard* boundary), and
> `HujahPolicy#create?` parent-visibility (C-1). Simplicity: accepted-only `following`/`followers` via the
> **through-association scope**; **3-state follow button**; accept-notification in the **model**
> (`after_update_commit`); `find_or_initialize_by` + explicit status; **defer the `/follow_requests` inbox
> page** (accept/decline from the notification card); private→public auto-accept via `update_all`; don't
> memoize `visible_to?`.

## Goal

A user can make their account **private**: their content (top-level hoojahs, replies, debate turns) and
profile hoojah-list/followers-list are visible only to **accepted followers** (+ themselves), and
following them is a **request → approve** flow. Public accounts (default) unchanged.

## The single gate

`User#visible_to?(viewer) = !private? || viewer == self || accepted_follower?(viewer)`
where `accepted_follower?(v) = v && passive_follows.accepted.exists?(follower_id: v.id)`.
`Hujah#visible_to?(viewer) = user.visible_to?(viewer)`. **Every content surface below goes through this.**
Not memoized (the list surfaces use SQL, the rest call it once).

## Schema + follow status

- `add_column :users, :private, :boolean, default: false, null: false`.
- `add_column :follows, :status, :integer, default: 0, null: false` (`enum status: { pending: 0,
  accepted: 1 }`); **backfill existing → accepted**.
- `Follow` scope `accepted`. **`User#following`/`#followers` accepted-only via the through scope:**
  `has_many :following, -> { where(follows: { status: :accepted }) }, through: :active_follows, source:
  :followed` (and the passive side) → `following_ids`, counts, lists all become accepted-only in one edit.
  (Confirmed safe: Slice-7 reciprocal-follow `delete_all` targets `Follow` directly, all statuses.)

## Follow flow (request → approve)

- **`FollowsController#create`:** `f = current_user.active_follows.find_or_initialize_by(followed: @target);
  f.status = @target.private? ? :pending : :accepted if f.new_record?; f.save` (rescue `RecordNotUnique`).
  (The pending default is security-conservative — a forgotten status is inert, not a leak.)
- **`Follow` model (all notifications/badges in the model, gated on accepted):**
  - `after_create_commit`: if `accepted?` → `notify_followed` (`new_follower`) + `UserBadge.award(followed,
    "first_follower")`; if `pending?` → `follow_request` notification to the target.
  - `after_update_commit :notify_accepted, if: -> { saved_change_to_status? && accepted? }` → `follow_accepted`
    to the requester + `new_follower` + `UserBadge.award(followed, "first_follower")`.
  - **Fixes the v1 bug:** `award_first_follower` must NOT fire on a pending request.
- **`FollowRequestsController`** (no index — deferred): `update` (accept → `@follow.update!(status:
  :accepted)`) and `destroy` (decline → `@follow.destroy`). `authenticate_user!` +
  `authorize @follow, :update?/:destroy?`. `FollowRequestPolicy#update?/#destroy? = record.followed_id ==
  user.id` (only the followed user acts). Requests are managed **from the `follow_request` notification
  card** (accept/decline `button_to`s). Cancelling your own pending request reuses the existing unfollow.
- **Button** (`_follow_button`): **3-state** — Following (accepted) / Requested
  (`current_user.active_follows.pending.exists?(followed_id: user.id)`) / Follow. (Unblock from Slice 7.)
- Notification enum append `follow_request: 12, follow_accepted: 13`; card branches (accept/decline for
  `follow_request`; link to profile for `follow_accepted`).

## Visibility gates (every content surface)

1. **Global feed** (`HujahsController#index` else-branch): `.joins(:user).where(users: { private: false })`
   — **UNCONDITIONAL** (anonymous too; do NOT wrap in `if user_signed_in?`).
2. **Following feed** (`timeline_for`): unchanged shape; accepted-only `following_ids` gates it.
3. **Trending** (`Hujah.trending`): query excludes private (`.joins(:user).where(users: {private: false})`);
   **AND** invalidate the cache on flip — `User after_update_commit { Rails.cache.delete("trending:v1") if
   saved_change_to_private? }` (T-1: else a cached hoojah stays visible ≤15 min after going private).
4. **Profile** (`UsersController#show`): if `!@user.visible_to?(current_user)` → **gated view**
   (avatar + name + @handle + "This account is private" + follow/request button + follower/following
   **counts only**; **no** hoojah list, headline, location, link, or badges — V-2 whitelist). Else full.
5. **Hoojah show** (`HujahsController#show`): `skip_authorization` → **`authorize @hujah`** with
   **`HujahPolicy#show? = record.user.visible_to?(user)`** (nil-safe; anonymous → Pundit rescue redirects,
   not a bare 403). Keep the Slice-7 `@children` block filter AND add the visibility filter (next).
6. **`@children`** (replies): **unconditional** per-viewer SQL predicate (reuses accepted-only ids):
   `visible_ids = user_signed_in? ? current_user.following_ids + [current_user.id] : []`;
   `@children = @children.joins(:user).where("users.private = false OR hujahs.user_id IN (?)", visible_ids)`
   (no N+1; accepted followers see a private user's reply, strangers/anonymous don't).
7. **Followers/following lists** (`UsersController#followers`/`#following`, L-1): when
   `!@user.visible_to?(current_user)` → gated (redirect / empty). (Not in v1 — must-fix.)
8. **Debate transcript** (`DebatePolicy`, D-1): `show? = record.participant?(user) || (record.concluded? &&
   record.challenger.visible_to?(user) && record.opponent.visible_to?(user))`; the `Scope` (Debates lens
   on the hoojah page) must likewise exclude concluded debates whose participants aren't both visible.
9. **Notification render** (N-1): `_notification_card`'s hoojah-body branch →
   `elsif notification.hujah && notification.hujah.visible_to?(current_user)`; mirror the guard in
   `NotificationSerializer#hujah` (reachable from the HTML app).
10. **`HujahPolicy#create?`** (C-1): also require `record.parent.visible_to?(user)` for a reply (a
    non-follower must not write into a thread they can't see).
11. **`Api::V1` read endpoints** (A-1): gate `Api::V1::HujahsController#index/#show` (exclude/deny private
    authors) + `Api::V1::UsersController#show` with `visible_to?`. Full native parity (serializer children,
    etc.) stays deferred to Project 3, but the raw content the feature hides must not be one guessable URL
    away.

**Mentions:** a private user can still be mentioned/notified (being addressed isn't gated content); the
mention links to their gated profile — no change (but the notification's *hoojah body* is gated by N-1).

## Toggle

`private` rides the profile-edit form (`user_params` += `:private`). **private→public:**
`current_user.passive_follows.pending.update_all(status: :accepted)` (bulk, no notification blast).
**public→private:** existing accepted followers stay; new follows become requests.

## Testing (visibility completeness is the property)

- **Model:** `visible_to?` (public→all; private→self+accepted only, NOT pending/stranger/anonymous);
  `following`/`followers` accepted-only; `Hujah#visible_to?`.
- **Follow flow:** public target → accepted + `new_follower` + badge; private target → pending +
  `follow_request` (no `new_follower`/badge yet); accept → accepted + `new_follower` + `follow_accepted` +
  badge; decline → removed; only the followed user accepts/declines (`FollowRequestPolicy`, else 403);
  3-state button; public follow lands `accepted` (enum-default footgun test).
- **Every gate (must each have a test):** private author absent from global feed + trending **for
  anonymous and strangers**; present in an accepted follower's Following feed; gated profile (no hoojah
  list); hoojah show 403/redirect for non-followers; `@children` hides a private replier from
  non-followers (incl. anonymous) but not from accepted followers; **followers/following list gated**;
  **concluded debate transcript hidden** from a non-follower of a private participant; **notification body**
  of a private hoojah not rendered to a non-follower; `Api::V1` hoojah/user endpoints gate a private
  author; `HujahPolicy#create?` rejects a reply to an unseen private parent. Public users unchanged.
- **Toggle:** private→public auto-accepts pending; trending cache invalidated on flip.
- **System (cuprite):** make private → stranger sees gated profile; accept a request → requester then sees
  content.
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Risks / notes

- **Count leaks (pre-existing, Low):** `children_count`/`hujah_count`/`vote_count` count unfiltered rows
  (same as Slice 7); a private author's reply still nudges a counter by 1. Noted, not fixed here.
- **Api::V1 full parity** (serializer children/parent, notifications) beyond the gated index/show/user is
  deferred to Project 3 — documented.
- **Block + private:** confirmed compatible (block's `delete_all` is status-unscoped; block gates are
  independent and compose).
- `private` column name is AR-safe (`private?`/`private=` generated; no `DangerousAttributeError`).

## Deferred

`/follow_requests` inbox page (7b-ii, UI polish); full `Api::V1` visibility parity; DMs; visibility tiers.
Then debate Increments (Slice 8), Project 3.
