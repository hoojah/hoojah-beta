# Slice 7: Block (interaction safety)

_Design spec. Date: 2026-08-05. Status: **design (from social sketch)**, pending specialist review + plan.
"Land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`). The safety slice the
earlier slices' "re-check when block ships" notes depend on._

## Context

Shipped through Slice 6. Everything is public + interactive. This slice adds **Block** — a bidirectional
invisibility/interaction cutoff between two users — closing the harassment gaps flagged in Slices 3–6.
**Mute** (a one-directional, silent "hide their content from me") and **private accounts** (visibility
gating of profiles/show pages) are their own later slices (7b) — this slice is Block only.

## Goals

When A blocks B (bidirectional effect — neither sees/reaches the other):
1. **Feeds** (following + global "Everyone") exclude each other's hoojahs.
2. **Trending** excludes each other's hoojahs (per-viewer, over the global cache).
3. **Follow** between them is impossible; **blocking removes any existing follow both ways**.
4. **No cross-user notification** is created between them (mention / new_follower / new_hoojah_response /
   new_vote / debate_*).
5. **Debate challenge** between them is rejected.
6. A **Block/Unblock** control on the profile + a **blocked-users list**.

## Non-goals (deferred)

Mute (one-directional); private accounts / profile+show-page hiding (Slice 7b — Block MVP does NOT hide a
blocked user's profile or a hoojah show page reached by direct URL; it removes them from feeds/trending and
cuts interaction/notification); reporting/admin moderation.

## Architecture

### 1. Block model + the single source of truth

```
blocks
  blocker_id  bigint null: false FK→users
  blocked_id  bigint null: false FK→users
  timestamps
indexes: unique [blocker_id, blocked_id]; [blocked_id]
DB check: blocker_id <> blocked_id
```
`Block belongs_to :blocker/:blocked (class_name User); validates uniqueness scope; not-self validation`.
`User has_many :blocks_made` (fk blocker_id, dependent destroy), `:blocks_received` (fk blocked_id,
dependent destroy).

**The one helper every filter uses** (bidirectional):
```ruby
# User
def blocked_ids      = blocks_made.pluck(:blocked_id)
def hidden_user_ids  = (blocks_made.pluck(:blocked_id) + blocks_received.pluck(:blocker_id)).uniq
```
`hidden_user_ids` = users I blocked ∪ users who blocked me. **Every visibility/notification filter goes
through this one method** so completeness is auditable in one place.

### 2. Filter surfaces (all driven by `hidden_user_ids`)

- **Feed — `Hujah.timeline_for`** (`app/models/hujah.rb:18`): append
  `.where.not(user_id: user.hidden_user_ids)`.
- **Feed — global** (`HujahsController#index` else-branch, `app/controllers/hujahs_controller.rb:11`): when
  `user_signed_in?`, add `.where.not(user_id: current_user.hidden_user_ids)`. (Anonymous: no blocks, no
  filter.)
- **Trending** (`Hujah.trending`, cached global ids): the cache stays global; **post-filter per viewer** —
  `TrendingController#index` does `@hujahs = Hujah.trending; @hujahs = @hujahs.reject { |h|
  current_user.hidden_user_ids.include?(h.user_id) } if user_signed_in?`. (Don't put the viewer's blocks
  in the shared cache.)
- **Mentions** (`Hujah#notify_mentions`, `hujah.rb:127`): skip a mentioned user whose id is in the
  author's `hidden_user_ids` (add `.where.not(id: author.hidden_user_ids)` to the lookup).
- **Notifications generally** — a **guard in the notify helpers**: `Notification` creation for a
  cross-user event is skipped when `recipient`'s id is in the actor's `hidden_user_ids` (or vice versa).
  Cleanest: a `Notification.notify(user:, actor:, ...)` helper that returns early when
  `actor && user && actor.hidden_user_ids.include?(user.id)`. Route `notify_parent_owner`, `cast_vote`'s
  `new_vote`, `notify_mentions`, `Follow#notify_followed`, and the `Debate` notifications through it (or an
  inline guard). **This is the completeness-critical change** — audit every `Notification.create!` that has
  a distinct actor+recipient.
- **Follow** (`FollowsController#create`): reject (flash / no-op) when the pair is blocked either way
  (`current_user.hidden_user_ids.include?(@target.id)`).
- **Debate challenge** (`DebatesController#create`): reject (422/flash) when
  `current_user.hidden_user_ids.include?(opponent.id)`.

### 3. Block controller + reciprocal-follow removal

- Routes: `post "/u/:username/block", to: "blocks#create", as: :block_user`;
  `delete "/u/:username/block", to: "blocks#destroy", as: :unblock_user`; `get "/blocks", to: "blocks#index"`
  (current_user's blocked list). Main routes (CSRF on), not `Api::V1`.
- `BlocksController` (`authenticate_user!`): `create` — `authorize Block.new(blocker: current_user,
  blocked: @target), :create?`; `current_user.blocks_made.find_or_create_by(blocked: @target)` (rescue
  `RecordNotUnique`); **remove reciprocal follows both ways** (`Follow.where(follower: [me, target],
  followed: [me, target]).where("follower_id IN (?) AND followed_id IN (?)", [me,target], [me,target])` —
  or simply delete the two possible follow rows between the pair). Turbo-Stream replace the profile
  action button (Block↔Unblock, and hide the Follow button while blocked). `destroy` — remove the block.
  `index` — `skip_authorization`, list `current_user.blocks_made` targets.
- `BlockPolicy#create? = user.present?`; `destroy? = record.blocker_id == user.id`.
- **Profile action area** (`_profile_header`/`_follow_button`): when blocked-by-me, show **Unblock** (no
  Follow); a "Block" item (e.g. in a small menu) otherwise. Don't show Follow for a hidden pair.
- **rack-attack:** a `block/user` throttle on `POST/DELETE /u/:username/block`.

## Component boundaries

- `Block` model; `User#hidden_user_ids`/`blocked_ids` + `blocks_made`/`blocks_received`.
- `BlocksController` (create/destroy/index); `BlockPolicy`.
- The single `Notification.notify` guard helper (or inline guards) + the 5 filter edits (timeline scope,
  global feed, trending post-filter, mention lookup, follow + debate rejections).
- Views: profile Block/Unblock control; `blocks/index` list; reuse Turbo-Stream button pattern. No Stimulus.
- rack-attack: `block/user` throttle.

## Testing (completeness is the whole point)

- **Model:** `Block` self-block rejected + unique; `hidden_user_ids` is bidirectional (A blocks B →
  B ∈ A.hidden and A ∈ B.hidden); blocking removes reciprocal follows both ways.
- **Feeds:** after A blocks B, A's global feed and following feed exclude B's hoojahs **and** B's exclude
  A's; a non-blocked stranger still sees both.
- **Trending:** A's `/trending` excludes B's hoojahs after a block (and anonymous trending is unfiltered).
- **Notifications:** a mention / follow-attempt / reply / vote / debate action between a blocked pair
  creates **no** notification (one test per notification category that has a distinct actor).
- **Interactions:** A cannot follow B while blocked (and blocking removed the existing follow); A cannot
  challenge B to a debate (422/flash).
- **Controller:** block/unblock Turbo-Stream (button flips; Follow hidden while blocked); `BlockPolicy`
  (unauth create → 401, non-owner destroy → 403); blocked list renders; throttle fires.
- **System (cuprite):** block from a profile → the Follow button is replaced by Unblock; (optionally) the
  blocked user's hoojah disappears from the feed on reload.
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Risks / open questions

- **Filter completeness is the security property.** The `hidden_user_ids` single-helper design makes it
  auditable; the security review must confirm *every* content/notification/interaction surface is covered
  (feeds ×2, trending, mentions, all notification callbacks, follow, debate). A missed surface = the
  harassment the feature is meant to stop.
- **Direct-URL access:** Block MVP does NOT hide a blocked user's **profile** or a **hoojah show page**
  reached by direct link (that's private-accounts, Slice 7b). A blocked user can still *read* public
  content by URL; they just can't interact (follow/challenge) or notify, and content is gone from
  feeds/trending. Document this boundary explicitly so it isn't mistaken for a leak.
- **Debate in progress when a block happens:** an active debate between the pair — MVP leaves it (turns
  still allowed; it's a mutual prior engagement). Note; could auto-conclude later.
- **Performance:** `hidden_user_ids` is two small `pluck`s per request that needs it; fine at beta scale;
  memoize per request if a page calls it repeatedly.

## Deferred

Mute (one-directional); private accounts + profile/show-page visibility gating (Slice 7b); auto-conclude a
blocked-pair debate; reporting/admin. Then debate Increments (Slice 8), Project 3.
