# Slice 6: Achievement Badges + Trending

_Design spec. Date: 2026-08-05. Status: **design + specialist-reviewed** (security, simplicity — folded,
v2). "Land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`)._

> **Review incorporation (v2). Critical (both reviews, independently):** the vote-milestone badges would
> run a badge insert inside `cast_vote`'s open `transaction`; a duplicate insert raises `RecordNotUnique`
> which **poisons the vote transaction on Postgres → the vote is lost**. **Fix: cut the vote-milestone
> badges entirely** (also removes the single-account self-vote farming vector). Net: **4 event-driven
> badges**, all off `after_create_commit`/`conclude!`, never nested in a hot-path transaction. Also:
> `UserBadge.award` uses an `exists?` guard; `User#badges` uses `filter_map` (a stale/renamed registry key
> must not 500 the public profile); `badge_earned` notification gets a mark-read affordance; a computed
> `badge` serializer attribute for API parity; trending is `Hujah.trending` (not a new PORO) with plain HN
> gravity on totals.

## Context

Shipped through Slice 5. The "engagement" slice: **achievement badges** on profiles + a **trending**
sidebar. **No background jobs** — badges award inline in existing callbacks; trending computes on read via
`Rails.cache.fetch` (Solid Cache configured). (Simplicity noted badges + trending share nothing and could
split; kept together as one small slice since each is now minimal.)

## Goals

1. **Badges** — 4 event-driven public achievements (first hoojah, first argument, first follower, first
   debate); profile chips; a `badge_earned` notification.
2. **Trending** — a lazily-loaded, cached sidebar of trending hoojahs (HN-decayed activity).

## Non-goals (deferred)

**Vote-milestone badges** (`ten_votes`/`hundred_votes` — hot-path transaction hazard + farmable; revisit
with distinct-voter counting after the Slice 5 public-count follow-up); `debate_won` (needs the verdict
increment, Slice 8); Solid Queue recurring trending; badge admin UI / leaderboards / rarity.

## Locked decisions

| Decision | Choice |
|---|---|
| Badge definitions | Ruby registry constant `Badge::REGISTRY` (code, not a table); only *awards* persist |
| Badge set | **4 event-driven**: `first_hoojah`, `first_argument`, `first_follower`, `first_debate` (NO vote milestones) |
| Award | Inline in existing `after_create_commit`/`conclude!` callbacks; idempotent (`exists?` guard + unique index) |
| Trending compute | `Rails.cache.fetch("trending:v1", expires_in: 15.minutes)` on read; `Hujah.trending` class method |
| Trending UI | lazy `turbo_frame` sidebar (`hidden lg:block`) + a standalone `/trending` page (same source) |

## Architecture

### 1. Badges

**Registry (no table):** `app/models/badge.rb` — `Badge::REGISTRY = { "first_hoojah" => { name:,
description:, icon: }, "first_argument" => {…}, "first_follower" => {…}, "first_debate" => {…} }` (Lucide
icons, e.g. `award`/`message-circle`/`users`/`swords`).

**Awards table:** `user_badges (user_id FK, badge_key string, timestamps)`, unique `[user_id, badge_key]`,
index `[user_id]`. `UserBadge belongs_to :user; validates :badge_key, inclusion: { in: Badge::REGISTRY.keys }`.
`User has_many :user_badges, dependent: :destroy`; **`def badges = user_badges.filter_map { |ub|
Badge::REGISTRY[ub.badge_key] }`** (`filter_map` drops any award whose key no longer exists in the
registry — prevents a public-profile 500 after a future registry edit).

**Awarding — idempotent, inline, off the hot path:**
```ruby
def self.award(user, key)
  return if user.user_badges.exists?(badge_key: key)   # cheap guard (avoids a guaranteed-fail insert)
  user.user_badges.create!(badge_key: key)
  Notification.create!(user:, category: :badge_earned, body: key)
rescue ActiveRecord::RecordNotUnique
  nil                                                  # race: already earned — no-op, no dup notification
end
```
Call sites — all fire **after commit / outside any hot-path transaction** (never inside `cast_vote`'s
transaction):
- `Hujah after_create_commit`: `UserBadge.award(user, is_parent? ? "first_hoojah" : "first_argument")`.
- `Follow after_create_commit`: `UserBadge.award(followed, "first_follower")`.
- `Debate#conclude!` (after the status update commits): `UserBadge.award(challenger, "first_debate");
  UserBadge.award(opponent, "first_debate")`.

**Notification:** append `badge_earned: 11`; `subject_user_id` nil; `body` = badge key. `_notification_card`
gets a `badge_earned` branch: Lucide `award` + "You earned the **<%= Badge::REGISTRY[body][:name] %>**
badge" (name from the registry, not raw input) **plus a mark-read `button_to`** (the existing card only
shows mark-read for `announcement`/hujah-present notifications; `badge_earned` has neither, so add one —
e.g. mark-read → the user's own profile). `NotificationSerializer` gains a computed `badge` attribute
(`{ key:, name:, icon: }` from the registry) for API/native parity (mirrors the `hujah`/`subject_user`
computed-attribute pattern). Profile header renders `@user.badges` as Lucide chips with `title` tooltips
(public).

### 2. Trending

**`Hujah.trending`** (class method, not a new model):
```ruby
def self.trending
  ids = Rails.cache.fetch("trending:v1", expires_in: 15.minutes) do
    where(parent_id: nil).where("updated_at > ?", 48.hours.ago).to_a
      .map { |h| [h.id, ((h.agree_count + h.neutral_count + h.disagree_count + h.children.size).to_f /
                          ((Time.current - h.created_at) / 3600 + 2)**1.5)] }
      .sort_by { |_, s| -s }.first(10).map(&:first)
  end
  where(id: ids).includes(:user).sort_by { |h| ids.index(h.id) }   # reload + preserve cache order
end
```
Plain HN gravity on **totals** (the `updated_at > 48h` candidate filter is the recency gate — voting bumps
`updated_at` via `increment!`). Cache stores ordered **ids** only. (If `children.size` per candidate is a
concern, precompute a grouped child count; at beta scale + a bounded 48h window it's fine.)

**UI:** `get "/trending", to: "trending#index"` (`TrendingController#index`, public, `skip_authorization`)
renders `_trending` (compact hoojah links + empty state). `hujahs/index` wraps its existing column in a
minimal `lg:grid`/`lg:flex` with an `<aside class="hidden lg:block">` holding
`turbo_frame_tag "trending", src: trending_path, loading: :lazy` (single column unchanged below `lg`).
`/trending` also renders as a standalone page (nav link) so it's reachable without a wide viewport. No
Stimulus, no gems.

## Component boundaries

- Models: `Badge` (registry), `UserBadge` (awards + `award`), `Hujah.trending` (cached); `User#badges`;
  award hooks in `Hujah`/`Follow`/`Debate`.
- Controller: `TrendingController#index` (public). Views: `_profile_header` chips; `_notification_card`
  `badge_earned` branch + mark-read; `_trending`; `hujahs/index` sidebar. Notification enum +`badge_earned`;
  `NotificationSerializer` computed `badge`. No jobs/Stimulus/gems.

## Testing

- **Badges:** `UserBadge.award` idempotent (twice → one row, one notification); first_hoojah on a top-level
  create, first_argument on a child, first_follower on a follow, first_debate on `conclude!` (both
  participants); `badge_earned` notification once; `User#badges` is nil-safe on a stale key (`filter_map`);
  `badge_key` inclusion validation; profile renders chips; the mark-read affordance works.
  **Regression: `cast_vote` still commits the vote and is unaffected** (no milestone check on the vote path).
- **Trending:** `Hujah.trending` returns recent higher-activity hoojahs in score order; cached (second call
  doesn't recompute — assert via query count / cache presence); `/trending` public (no auth) renders +
  empty state.
- **System (cuprite):** a badge chip appears on the profile after earning; the feed shows the trending
  sidebar on a wide viewport. (Reuse `login_as_system`.)
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Risks / open questions

- **Badge farming:** with vote-milestone badges cut, the 4 remaining are one-time event badges (first X) —
  not farmable for a running count. (The self-vote path that made milestones cheaply farmable, and the raw
  public vote counts, remain the Slice 5 tracked follow-up; note `cast_vote` has no self-vote guard.)
- **Trending gaming:** vote/argument brigading to climb; recency decay + top-10 cap limit blast radius;
  distinct-voter weighting is a later refinement.
- **Cache stampede/staleness:** `Rails.cache.fetch` may let a few requests recompute on expiry; cheap at
  beta scale (bounded window, top-10). Move to a recurring job only if it grows.
- **Trending privacy:** public top-level hoojahs only (no private/blocked content exists yet); **re-check
  when Slice 7 (Block/mute) ships** — trending candidates must then exclude blocked/private.
- **HTML vote endpoint** (`POST /hoojah/:slug/votes`) isn't in the rack-attack `votes/user` throttle
  (pre-existing; only the API path is) — note for the rack-attack owner, out of scope here.

## Deferred

`debate_won` (Slice 8 verdict); vote-milestone badges with distinct-voter counting; recurring-job trending.
Then Block/mute (Slice 7), debate Increments (Slice 8), Project 3.
