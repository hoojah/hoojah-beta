# Slice 6: Achievement Badges + Trending

_Design spec. Date: 2026-08-05. Status: **design (from roadmap/social sketch)**, pending specialist review
+ plan. "Land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`)._

## Context

Shipped through Slice 5. This is the "engagement" slice from the social sketch: **achievement badges** on
profiles + a **trending** sidebar. Deliberately **no background jobs** for MVP — badges award inline in
existing callbacks; trending computes on read via `Rails.cache.fetch` (Solid Cache is configured). This
avoids standing up a Solid Queue worker in dev/test.

## Goals

1. **Badges** — users earn public achievement badges (first hoojah, first argument, first follower,
   vote-count milestones, first debate); shown as chips on the profile; a `badge_earned` notification.
2. **Trending** — a lazily-loaded sidebar of currently-trending hoojahs (recency-decayed activity),
   cached, shown on wide screens.

## Non-goals (deferred)

Solid Queue recurring job for trending (cache-on-read is enough at beta scale — revisit if compute grows);
`debate_won` badge (needs the verdict increment, Slice 8); badge admin UI; leaderboards; per-badge rarity.

## Locked decisions (defaults; flagged for review)

| Decision | Choice |
|---|---|
| Badge definitions | **Ruby registry constant** (`Badge::REGISTRY`), not a DB table — adding a badge is a code change (fine for a solo beta); only *awards* are persisted |
| Badge award | **Inline** in existing model callbacks (no job), idempotent via a unique index |
| Trending compute | **`Rails.cache.fetch("trending", expires_in: 15.minutes)`** on read (no recurring job/worker) |
| Trending sidebar | **Lazy `turbo_frame`**, `hidden lg:block` (wide screens only) |

## Architecture

### 1. Badges

**Registry (definitions, no table):** `app/models/badge.rb` — `Badge::REGISTRY = { "first_hoojah" =>
{ name:, description:, icon: <lucide> }, "first_argument" => {…}, "first_follower" => {…},
"ten_votes" => {…}, "hundred_votes" => {…}, "first_debate" => {…} }`. (Icons from the Lucide set,
e.g. `award`/`star`/`users`/`trophy`.)

**Awards table:** `user_badges (user_id FK, badge_key string, timestamps)`, unique `[user_id, badge_key]`,
index `[user_id]`. `UserBadge belongs_to :user; validates badge_key inclusion in Badge::REGISTRY.keys`.
`User has_many :user_badges, dependent: :destroy`; `def badges = user_badges.map { |ub| Badge::REGISTRY[ub.badge_key] }`.

**Awarding — idempotent + inline:** `UserBadge.award(user, key)`:
```ruby
def self.award(user, key)
  ub = user.user_badges.create(badge_key: key)   # unique index → no dup
  Notification.create!(user:, category: :badge_earned, body: key) if ub.persisted?
rescue ActiveRecord::RecordNotUnique
  nil                                              # already earned — no-op
end
```
Wired into existing callbacks (each cheap, at beta scale):
- `Hujah after_create_commit`: `UserBadge.award(user, is_parent? ? "first_hoojah" : "first_argument")`
  (`is_parent?`/`has_parent?` already exist).
- `Hujah#cast_vote` (vote received): after updating counters, check the recipient's total votes
  received and award `ten_votes`/`hundred_votes` when the threshold is crossed
  (`UserBadge.award(hujah.user, "ten_votes")` — idempotent, so awarding at ">= 10" every time is fine).
- `Follow after_create_commit`: `UserBadge.award(followed, "first_follower")`.
- `Debate#conclude!`: `UserBadge.award(challenger, "first_debate"); UserBadge.award(opponent, "first_debate")`.

**Notification:** append `badge_earned: 11` to the enum; `subject_user_id` stays nil (it's about *you*);
`body` carries the badge key. `_notification_card` gets a `badge_earned` branch (Lucide `award` +
"You earned the **<name>** badge"). Profile header (`_profile_header`) renders `@user.badges` as Lucide
chips with `title` tooltips (public, no auth).

### 2. Trending

**Compute (on read, cached):** `Trending.hujahs` (PORO or `Hujah.trending` scope-ish class method):
```ruby
Rails.cache.fetch("trending:v1", expires_in: 15.minutes) do
  # candidates: top-level hoojahs with activity in the last 48h, HN-style decay
  Hujah.where(parent_id: nil).where("updated_at > ?", 48.hours.ago)
       .select("hujahs.*, (agree_count+neutral_count+disagree_count) AS votes")
       .map { |h| [h.id, score(h)] }.sort_by { |_, s| -s }.first(10).map(&:first)
end
```
`score = (recent_votes + recent_args) / (hours_since_created + 2) ** 1.5` (gravity). The cache stores just
the ordered **ids**; the sidebar loads `Hujah.where(id: ids).includes(:user)` and re-sorts to cache order
(one query, no N+1). Cache invalidation is purely time-based (15 min) — simple; slightly stale is fine.

**UI:** `get "/trending", to: "trending#index"` (`skip_authorization`, public) renders a `_trending`
partial (compact hoojah links). The feed/layout adds `turbo_frame_tag "trending", src: trending_path,
loading: :lazy` in a `hidden lg:block` sidebar column; `hujahs/index` becomes a feed+sidebar grid at `lg`
(single column below `lg`, unchanged). Empty state when nothing is trending. No Stimulus.

## Gem manifest

**None** (Solid Cache already present; no jobs).

## Component boundaries

- Models: `Badge` (registry constant), `UserBadge` (awards + `award` class method), `Trending` (cached
  compute); `User#badges`; callback hooks in `Hujah`/`Follow`/`Debate`.
- Controllers: `TrendingController#index` (public, `skip_authorization`).
- Views: `_profile_header` badge chips; `_notification_card` `badge_earned` branch; `_trending` +
  `hujahs/index` sidebar grid.
- Notification enum +`badge_earned`. No jobs, no Stimulus, no gems.

## Testing

- **Badges:** `UserBadge.award` is idempotent (awarding twice → one row, one notification); each trigger
  awards the right badge (first_hoojah on a top-level create, first_argument on a child, first_follower on
  a follow, ten_votes when the 10th vote lands, first_debate on conclude); `badge_earned` notification
  created once; profile renders earned chips; `badge_key` inclusion validation.
- **Trending:** `Trending.hujahs` returns recent, higher-activity hoojahs ordered by score; result is
  cached (second call doesn't recompute — assert via a query counter or cache presence); `/trending`
  renders (public, no auth) the trending partial + empty state; the sidebar is a lazy turbo_frame.
- **System (cuprite):** profile shows a badge chip after earning; the feed shows the trending sidebar on a
  wide viewport (reuse `login_as_system`).
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Risks / open questions

- **Badge farming:** vote-milestone badges can be farmed via alt-account votes (same underlying gaming as
  raw vote counts, which are already public+ungated — see Slice 5's tracked follow-up). MVP accepts this;
  a "distinct voters" refinement + the public-count suppression are a later hardening. Awards are
  immutable once earned.
- **Trending gaming:** vote/argument brigading to climb the sidebar; recency decay + the small top-10 cap
  limit blast radius. Consider excluding self-votes / weighting distinct voters later (note only).
- **Cache staleness / stampede:** `Rails.cache.fetch` can let a few concurrent requests recompute on
  expiry (no built-in lock). At beta scale the compute is cheap (bounded 48h window, top-10); acceptable.
  If it grows, move to the recurring-job approach the sketch described.
- **Trending privacy:** computed over public top-level hoojahs only — no private data (none exists);
  re-check when private/blocked content ships (Slice 7).

## Deferred

`debate_won` badge (Slice 8 verdict); recurring-job trending; distinct-voter badge hardening; leaderboards.
Then Block/mute (Slice 7), debate Increments (Slice 8), Project 3.
