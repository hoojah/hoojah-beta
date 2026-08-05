# Slice 7b: Private Accounts

_Design spec. Date: 2026-08-06. Status: **design (from social sketch)**, pending specialist review + plan.
"Land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`). Highest-blast-radius
visibility change — turns the "everything public" model into opt-in privacy._

## Context

Shipped through Slice 7 (Block). This adds **private accounts**: a user can make their account private, so
their content is visible only to **accepted followers** (+ themselves), and following them becomes a
**request → approve** flow. Public accounts (the default) are unchanged.

## Goals

1. **`users.private`** toggle (default false; on the profile-edit form).
2. **Follow request/approve** for private targets: following a private user creates a **pending** request;
   the private user **approves** (→ accepted) or **declines**. Following a public user stays instant.
3. **Visibility gating** — a private user's hoojahs (top-level + replies) and their profile hoojah-list are
   visible only to `visible_to?` viewers (self or accepted follower). Private users are **excluded from
   discovery** (global "Everyone" feed + trending).
4. Follow **counts/lists count only accepted** follows.

## Non-goals (deferred)

`Api::V1::*` private gating (consistent with the Block deferral — a future native client needs the same
gates); private DMs; per-hoojah visibility (privacy is per-account, all-or-nothing); approving with a
"close friends" tier; hiding a private user's *existence* (their name/handle/avatar + "private account"
state are still shown — like Instagram; only their *content* is gated).

## Architecture

### 1. Schema + core helpers

- `add_column :users, :private, :boolean, default: false, null: false` (+ index).
- `add_column :follows, :status, :integer, default: 0, null: false` (`enum status: { pending: 0,
  accepted: 1 }`); **backfill existing follows to `accepted`** (they predate privacy).
- `Follow` scope `accepted`. **`User#following`/`#followers` count/list ACCEPTED only** — change the
  `has_many :through` to go through an `accepted_active_follows`/`accepted_passive_follows` scope (or add
  `-> { accepted }` to the through associations). `following_ids` (used by `timeline_for`) must be
  accepted-only.
- **`User#visible_to?(viewer)`** = `!private? || viewer == self || accepted_follower?(viewer)` where
  `accepted_follower?(v) = v && passive_follows.accepted.exists?(follower_id: v.id)`.
- `Hujah#visible_to?(viewer) = user.visible_to?(viewer)`.

### 2. Follow flow (request → approve)

- **`FollowsController#create`:** `status = @target.private? ? :pending : :accepted`; build the follow with
  that status. Notification: private target → `follow_request` to the target; public → the existing
  `new_follower` (fired by `Follow after_create_commit` only when **accepted** — move `notify_followed` to
  fire on accepted, and add a `follow_request` notification for pending). Button state: **Follow** →
  **Requested** (pending) / **Following** (accepted) / **Unblock**-aware from Slice 7.
- **`FollowRequestsController`** (private user manages incoming requests): `index` (list
  `current_user.passive_follows.pending` requesters), `update`/`accept` (set accepted → notify requester
  `follow_accepted`, fire the normal `new_follower`), `destroy`/`decline` (delete the pending follow). All
  `authenticate_user!`; authorize the follow (only the followed user acts on their own request).
- Toggling **private → public**: auto-accept all pending requests (they'd be accepted on request anyway).
  **public → private**: existing accepted followers stay; new follows become requests.

### 3. Visibility gating (all via `visible_to?`)

- **Global feed** (`HujahsController#index` else-branch): exclude private authors —
  `.joins(:user).where(users: { private: false })` (private users are discovery-excluded; their content
  reaches followers via the Following feed). Applies to anonymous + signed-in.
- **Following feed** (`timeline_for`): unchanged in shape — but `following_ids` is now **accepted-only**, so
  a private user you follow (accepted) appears; one you've only *requested* does not. No extra gate needed
  (you're an accepted follower by construction).
- **Trending** (`Hujah.trending` candidates): exclude private authors —
  `.joins(:user).where(users: { private: false })`.
- **Profile** (`UsersController#show`): if `!@user.visible_to?(current_user)` → render the **gated view**
  (avatar/name/@handle + "This account is private" + a Follow/Requested button + follower/following counts
  only), **no hoojah list**. Else the full profile. `@user.followers`/`following` counts show accepted.
- **Hoojah show** (`HujahsController#show`): gate via Pundit — change `skip_authorization` to
  `authorize @hujah` with **`HujahPolicy#show? = record.user.visible_to?(user)`** (a private author's
  hoojah 403/redirects for non-followers). Keep the Slice-7 `@children` block filter; **also filter
  `@children` by author visibility** (`@children.select { |c| c.visible_to?(current_user) }` or a
  visible-authors scope) so a private replier's argument under a public hoojah is hidden from non-followers.
- **Mentions/notifications:** a private user can still be *mentioned* and notified (being addressed isn't
  gated content); the mention links to their (gated) profile. No change.

### 4. Notification enum

Append `follow_request: 12, follow_accepted: 13`. `_notification_card` branches: `follow_request`
(→ the requests inbox, "@x requested to follow you" — with accept/decline, or link to
`/follow_requests`), `follow_accepted` (→ the accepter's profile).

### 5. Pundit / routes

- `HujahPolicy#show?` (new — gates private authors). `HujahsController#show` switches to `authorize @hujah`.
  (index/new stay `skip_authorization`.)
- `FollowRequestPolicy` (only the followed user manages their requests): `update?/destroy? = record.followed_id
  == user.id`.
- Routes: `get "/follow_requests"` (index); `patch/delete "/follow_requests/:id"` (accept/decline); the
  `private` toggle rides the existing profile-edit form (`user_params` gains `:private`).
- rack-attack: the existing `follow/user` throttle covers request creation (same route).

## Component boundaries

- `User#private` + `visible_to?`/`accepted_follower?`; `Follow#status` + `accepted` scope + accepted-only
  `following`/`followers`. `Hujah#visible_to?`.
- `FollowsController#create` (pending vs accepted); `FollowRequestsController` (index/accept/decline);
  `FollowRequestPolicy`; `HujahPolicy#show?`; profile-edit `:private`.
- Views: gated profile view; `follow_requests/index`; button "Requested" state; `_notification_card`
  branches. Content-filter edits: global feed, trending, `@children`, `HujahsController#show` authorize.
- No Stimulus, no gems.

## Testing (visibility completeness is the property)

- **Model:** `visible_to?` (public → everyone; private → self + accepted follower only; not a
  pending-requester, not a stranger); `following`/`followers` count accepted only; `Hujah#visible_to?`.
- **Follow flow:** following a public user → accepted + `new_follower`; following a private user → pending +
  `follow_request` (no `new_follower` yet); the private user accepts → accepted + `new_follower` +
  `follow_accepted` to requester; decline → follow removed; only the followed user can accept/decline
  (`FollowRequestPolicy`, non-owner → 403).
- **Visibility:** a private user's top-level hoojahs are absent from the global feed + trending for
  everyone (incl. anonymous); present in an **accepted follower's** Following feed; a **stranger/pending**
  requester gets the gated profile (no hoojah list) and a **403/redirect on the hoojah show page**; an
  accepted follower + the owner see everything; a private user's reply under a public hoojah is hidden from
  non-followers in `@children`. Public users unchanged throughout.
- **Toggle:** private→public auto-accepts pending; public→private keeps existing accepted followers.
- **System (cuprite):** make account private → a stranger sees the gated profile; accept a follow request →
  the requester then sees the content.
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Risks / open questions

- **Completeness is the property** (like Block): the `visible_to?` helper is the single driver; the security
  review must confirm EVERY content surface (global feed, following feed, trending, profile hoojah-list,
  hoojah show, `@children`, and any serializer/API path) gates a private author. A missed surface leaks
  private content.
- **`Api::V1` gating deferred** — the JSON feed/children/user endpoints do NOT gate private authors yet
  (pre-existing lack of any visibility filtering; native client is Project 3). Documented, not silent.
- **Global-feed exclusion vs per-hoojah visibility:** MVP excludes private authors from the global feed
  wholesale (simpler + safe) rather than per-viewer per-hoojah inclusion; a private user's own global-feed
  view therefore omits their own posts (they see them on their profile/following). Acceptable MVP boundary.
- **Existing debates/mentions with a now-private user:** a private user in an active debate — the debate
  transcript is gated by `DebatePolicy#show?` (participants/concluded) already; confirm a private
  participant's turns aren't leaked to a non-follower via the (public, concluded) debate view — likely fine
  since debate visibility is its own gate, but flag for the review.
- **Counter/derived correctness:** switching `following`/`followers` to accepted-only must not break the
  Slice-3 profile counts or the Slice-7 reciprocal-follow-removal (which should target any-status follows).

## Deferred

`Api::V1` private gating; DMs; visibility tiers; then debate Increments (Slice 8), Project 3.
