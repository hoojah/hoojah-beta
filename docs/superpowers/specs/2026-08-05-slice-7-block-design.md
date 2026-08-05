# Slice 7: Block (interaction safety)

_Design spec. Date: 2026-08-05. Status: **design + specialist-reviewed** (security, simplicity — folded,
v2). "Land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`)._

> **Review incorporation (v2).** **Critical (security):** replies are unfiltered content — a blocked user
> could still reply under your hoojah. Fix by **enforcing block at the Pundit policy layer** (reject the
> *interaction*: reply/follow/challenge) — which then needs **zero notification-creation guards** (no
> reply → no `new_hoojah_response`; no follow → no `new_follower`; challenge rejected → no debate notif),
> plus **content filters** on both feeds + `@children` + trending, and the mention **query** filter.
> Dropped the `Notification.notify` helper, the debate-notification guard (would stall an active debate —
> both reviews), the `new_vote` guard (anonymous, no vector) and dead `blocked_ids`. **Memoize**
> `hidden_user_ids`; reciprocal-follow removal is a one-line `delete_all` in a transaction; block/debate
> rejections live in the policies (avoids the `verify_authorized` 500 landmine).

## Context

Shipped through Slice 6. Everything is public + interactive. This slice adds **Block** — a bidirectional
invisibility/interaction cutoff — closing the harassment gaps flagged in Slices 3–6. **Mute** and
**private accounts** (profile/show-page hiding) are Slice 7b.

## Goals

When A blocks B (bidirectional — neither sees/reaches the other):
1. **Feeds** (following + global) and a hoojah's **reply thread** exclude each other's content.
2. **Trending** excludes each other's hoojahs (per-viewer, over the global cache).
3. **Interactions rejected** (via policy): B can't **reply** to A's hoojah, **follow** A, or **challenge** A
   to a debate (and vice versa) → no such content and no such notification is ever created.
4. **Blocking removes any existing follow both ways.**
5. A **Block/Unblock** control on the profile + a **blocked-users list**.

## Non-goals (deferred)

Mute (one-directional); private accounts / profile+show-page hiding (Slice 7b — Block MVP does NOT hide a
blocked user's profile/show page/appearance in third-party followers-following lists reached by direct
URL); rejecting a **vote** between a blocked pair (votes are anonymous — `new_vote` carries no
`subject_user_id`; no attribution, no harassment vector — deliberately not filtered); block filtering of
the `Api::V1::*` JSON feed/children/user endpoints (**deferred, not ignored** — those have no social-graph
filtering today; a future native client needs the same filters incl. `HujahSerializer#children`);
auto-concluding an in-progress debate on block (grandfathered — its notifications keep firing).

## Architecture

### 1. Block model + the single source of truth

```
blocks
  blocker_id bigint null: false FK→users
  blocked_id bigint null: false FK→users
  timestamps
indexes: unique [blocker_id, blocked_id]; [blocked_id]
DB check: blocker_id <> blocked_id
```
`Block belongs_to :blocker/:blocked (class_name User); validates uniqueness scope; not_self`.
`User has_many :blocks_made` (fk blocker_id, dep destroy), `:blocks_received` (fk blocked_id, dep destroy).

**The one memoized helper every filter/policy uses (bidirectional):**
```ruby
def hidden_user_ids
  @hidden_user_ids ||= (blocks_made.pluck(:blocked_id) + blocks_received.pluck(:blocker_id)).uniq
end
```
(Memoization matters: the trending post-filter consults it per candidate. `current_user` is one memoized
instance/request, so this is safe.) No `blocked_ids` (dead). Update the stale
`following_ids - blocked_ids` comment at `hujah.rb:16-17`.

### 2. Enforce block at the POLICY layer (rejections), not controller guards

Pushing the check into policies keeps denials flowing through the app's existing
`rescue_from Pundit::NotAuthorizedError` and avoids an early-`return`-before-`authorize`
`verify_authorized` 500. The existing `authorize` calls are unchanged.

- **`HujahPolicy#create?`** — reject a reply to a hidden pair's hoojah:
  `user.present? && (record.parent_id.nil? || !user.hidden_user_ids.include?(record.parent&.user_id))`.
  **Controller change (security-flagged):** `HujahsController#create` currently `authorize Hujah`
  (class-level) — switch to building `@hujah` with its `parent_id` first, then `authorize @hujah`
  (instance), so the policy can read `record.parent.user_id`.
- **`FollowPolicy#create?`** = `user.present? && !user.hidden_user_ids.include?(record.followed_id)`.
- **`DebatePolicy#create?`** = `user.present? && !user.hidden_user_ids.include?(record.opponent_id)`.

Because the interactions are rejected, **no notification guard is needed** for `new_hoojah_response`,
`new_follower`, or `debate_*` (new). `mention` is filtered at its query (below). `new_vote` is left alone
(anonymous). Net: **no `Notification.create!` call site changes** except the mention query.

### 3. Content filters (all via `hidden_user_ids`, signed-in only)

- **`Hujah.timeline_for`** (`hujah.rb:18`): append `.where.not(user_id: user.hidden_user_ids)` (insurance;
  follow-removal already excludes blocked from `following_ids`).
- **Global feed** (`HujahsController#index` else-branch): when `user_signed_in?`, add
  `.where.not(user_id: current_user.hidden_user_ids)`.
- **Reply thread** (`HujahsController#show` `@children`): when `user_signed_in?`,
  `@children = @children.where.not(user_id: current_user.hidden_user_ids)` (the Critical fix — hides
  pre-block replies from a now-blocked author; new ones are rejected at create per §2).
- **Trending** (`TrendingController#index`): keep the cache global; `@hujahs = Hujah.trending;
  @hujahs = @hujahs.reject { |h| current_user.hidden_user_ids.include?(h.user_id) } if user_signed_in?`.
- **Mentions** (`Hujah#notify_mentions`, `hujah.rb:127`): add `.where.not(id: author.hidden_user_ids)` to
  the user lookup.

### 4. Block controller + reciprocal-follow removal

- Routes (main, CSRF on): `post/delete "/u/:username/block"` (`blocks#create`/`#destroy`, as
  `block_user`/`unblock_user`); `get "/blocks"` (`blocks#index`, current_user's blocked list).
- `BlocksController` (`authenticate_user!`, `set_target` from `:username`):
  - `create`: `authorize Block.new(blocker: current_user, blocked: @target), :create?`; then in a
    **transaction**: `current_user.blocks_made.find_or_create_by(blocked: @target)` (rescue
    `RecordNotUnique`) **and** `Follow.where(follower: [current_user, @target], followed: [current_user,
    @target]).delete_all` (one line; `delete_all` since Follow has no destroy callbacks). Turbo-Stream
    replace the profile action button (Block↔Unblock; Follow hidden while blocked).
  - `destroy`: `@block = current_user.blocks_made.find_by(blocked: @target); authorize @block, :destroy? if
    @block; skip_authorization if @block.nil?; @block&.destroy` (mirror `FollowsController#destroy` — the
    `skip_authorization` on nil is required or `verify_authorized` 500s).
  - `index`: `skip_authorization`; list `current_user.blocks_made` targets.
- `BlockPolicy#create? = user.present?`; `destroy? = record.blocker_id == user.id`.
- **Profile action area** (`_follow_button`/`_profile_header`): blocked-by-me → **Unblock** (no Follow); a
  "Block" affordance otherwise; never show Follow for a hidden pair.
- **rack-attack:** `block/user` throttle on `POST/DELETE /u/:username/block`.

## Component boundaries

- `Block` model; `User#hidden_user_ids` + `blocks_made`/`blocks_received`.
- `BlocksController` (create/destroy/index); `BlockPolicy`.
- Policy edits: `HujahPolicy#create?` (+ the controller instance-authorize change), `FollowPolicy#create?`,
  `DebatePolicy#create?`. Content-filter edits: `timeline_for`, global feed, `@children`, trending, mention
  query. No notification-creation changes. No Stimulus, no gems.

## Testing (completeness is the property)

- **Model:** `Block` self-block rejected (validation + DB check) + unique; `hidden_user_ids` bidirectional;
  blocking removes reciprocal follows both ways (in one transaction).
- **Content:** after A blocks B — A's global feed, following feed, and any hoojah's reply thread exclude B's
  content **and** B's exclude A's; a stranger still sees both; A's `/trending` excludes B; anonymous
  trending unfiltered.
- **Interactions rejected (policy):** B can't reply to A's hoojah (403), can't follow A, can't challenge A
  to a debate — **and no `new_hoojah_response`/`new_follower`/`debate_challenge` notification is created**
  in each case. A mention of a blocked user creates no `mention` notification. A `new_vote` between a
  blocked pair IS still created (deliberate — anonymous).
- **In-progress debate grandfathered:** an active debate that predates the block still allows turns AND
  still fires `debate_your_turn`/`debate_concluded` (no stall).
- **Controller:** block/unblock Turbo-Stream (button flips; Follow hidden while blocked); `BlockPolicy`
  (unauth create → 401, non-owner destroy → 403); `#destroy` on a non-existent block doesn't 500; blocked
  list renders; throttle fires.
- **System (cuprite):** block from a profile → Follow replaced by Unblock; the blocked user's hoojah is
  gone from the feed on reload.
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Risks / open questions

- **Completeness** is the security property; the single `hidden_user_ids` helper + policy-layer rejection
  keep it auditable. The security review confirmed the 5 notification sites and the reply-content gap;
  this design closes them.
- **Direct-URL boundary (documented):** Block MVP does NOT hide a blocked user's profile, hoojah show
  page, or their appearance in third-party followers/following lists reached by URL — that's Slice 7b
  (private accounts). Block removes them from *your* feeds/threads/trending and cuts interaction/notification.
- **`Api::V1` parity:** deferred (pre-existing lack of any social-graph filtering); a native client needs
  the same feed/children filters incl. `HujahSerializer#children`.
- **Follow/block race:** a follow created in the same instant as the block may escape the one-time cleanup;
  the create-in-a-transaction narrows it; residual self-corrects on the next block cycle. Accept for MVP.

## Deferred

Mute; private accounts + profile/show/listing visibility gating (Slice 7b); `Api::V1` block filters;
auto-conclude a blocked-pair debate. Then debate Increments (Slice 8), Project 3.
