# Slice 5: Vote-Privacy Hardening + User Analytics (MVP)

_Design spec. Date: 2026-08-05. Status: **design (from roadmap sketch)**, pending specialist review +
plan. "Land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`)._

## Context

Shipped: feed/voting/arguments/compose/profile/notifications/flags/share, Devise, Pundit, Slice 3 social,
Slice 4 debate. This slice does two related things: (1) close the **pre-existing vote-privacy leak** the
analytics research surfaced, then (2) ship a **privacy-first, owner-only analytics dashboard** built so it
can never re-open that leak. Privacy is the central constraint.

## Part A — Vote-privacy hardening (do first)

**The leak:** `Hujah#cast_vote` creates `Notification.create!(category: :new_vote, subject_user_id: by.id)`
(`app/models/hujah.rb:55`), and `NotificationSerializer` exposes `subject_user: { username }`. So
`Api::V1::NotificationsController#index` hands a hoojah **owner the username (+ the notification's
timestamp) of everyone who first-voted on their hoojah** — while the vote *choice* stays secret. Votes are
meant to be an effectively secret ballot; this identity+timestamp seam is the top de-anonymization vector
(correlate a named first-voter to any future choice-split analytics).

**Fix (source, not serializer):**
1. **Drop `subject_user_id` from the `new_vote` notification** in `cast_vote` — it serves no display
   purpose (the HTML `_notification_card` `new_vote` branch says "you have a new vote on your hoojah",
   no username; confirm at build). No data stored → nothing to leak.
2. **Backfill migration:** `Notification.where(category: :new_vote).update_all(subject_user_id: nil)` to
   scrub existing rows.
3. Keep `subject_user_id` for `new_hoojah_response`, `mention`, `new_follower`, `debate_*` — those
   legitimately name a public actor (a reply/mention/follow/challenge is a public act; a vote is not).
4. Spec/regression: `cast_vote` creates a `new_vote` notification **with `subject_user_id: nil`**; the API
   notifications serializer no longer returns a `subject_user` for a `new_vote`.

This closes the leak and unblocks the analytics **trends** increment (deferred) safely.

## Part B — User Analytics dashboard (MVP)

### Goals

An **owner-only** dashboard where a user sees their own content's performance. **Never** exposes who voted
how. MVP = zero new tables, compute-on-read from the denormalized counts already on `hujahs`.

### Non-goals (later increments)

Trends over time (needs a rollup table + Solid Queue job; gated on Part A — later). Reach/impressions
(net-new privacy-reviewed instrumentation). Follower-growth analytics (depends on Slice 3 follow data;
could be a small add later). Any metric describing *voters* (behavioral) — out of scope without voter
opt-in.

### Metrics (MVP — all from `hujahs` denormalized counts, owner's own content)

- Per-hoojah vote distribution (agree/neutral/disagree + %), for the owner's top-level hoojahs.
- Totals: votes received (`SUM(agree+neutral+disagree)` over own hoojahs), arguments received (count of
  child hoojahs whose parent is the owner's).
- **Most divisive vs most consensus** hoojahs (ranking from each hoojah's own counts). Divisiveness =
  a tunable helper (e.g. normalized entropy, or `1 − |a−d|/(a+d)`); pick one, document it.

### Privacy gates (the core deliverable — hard invariants)

1. **Owner-only.** `/dashboard` → `AnalyticsController#show`, always `current_user` (no username in the
   URL, mirroring `/notifications`). `AnalyticsPolicy#show? = user.present? && record.id == user.id`.
2. **No surface ever joins `votes → users`.** No `VoteSerializer`, no votes-list, no per-voter data — MVP
   reads only aggregate counts off `hujahs`, so this holds by construction. Encode it as a rule.
3. **k-anonymity (k = 5).** Never render a per-hoojah breakdown when that hoojah's total votes `< 5` — show
   "fewer than 5 votes" instead of the split. (Prevents "1 person disagreed" + small-N inference.)
4. **No per-vote timestamps / no time series** in MVP (that's the later gated increment).
5. **API discipline:** no JSON analytics endpoint in MVP. If added later it reuses `AnalyticsPolicy`,
   serves only `current_user` aggregates, never accepts a `:username` for others, and is aggregate-only.

### Architecture

- **Compute-on-read, zero new tables.** All metrics are grouped SQL over `Hujah.where(user_id:
  current_user.id)` using the denormalized `agree_count`/`neutral_count`/`disagree_count` — one query,
  no votes scan, no N+1 (never per-hoojah queries). A `UserAnalytics` PORO/query object
  (`app/models/user_analytics.rb` or `app/queries/`) encapsulates the aggregates + the k-suppression, so
  the controller stays thin and the suppression lives at the data layer (not the view).
- **UI:** `GET /dashboard` (owner-only). **Server-rendered SVG / Tailwind bars — zero JS, CSP-clean** (the
  app already renders vote bars server-side in `_vote_bars`; reuse that idiom for distribution bars +
  a simple ranked list). No Chart.js / no importmap chart lib. Lazy `turbo_frame` per panel is optional
  (keeps the shell fast) but not required for MVP.
- Under Pundit `verify_authorized`: `AnalyticsController#show` → `authorize current_user, :show?,
  policy_class: AnalyticsPolicy` (or `authorize current_user` with an `AnalyticsPolicy`). Navbar gets a
  "Dashboard" link for signed-in users.

### Component boundaries

- `AnalyticsController#show` (thin); `UserAnalytics` query object (aggregates + k-suppression);
  `AnalyticsPolicy` (owner-only). Views: `analytics/show` + `_distribution_bar` / `_stat` partials
  (server SVG). Helper for the divisiveness score + the k-suppression display. No new Stimulus, no gems.

## Testing

- **Part A:** `cast_vote` → `new_vote` notification has `subject_user_id == nil`; the API notifications
  serializer returns no `subject_user` for a `new_vote`; other categories still carry it; backfill nulls
  existing `new_vote` rows.
- **Part B:** `/dashboard` requires login (unauth → redirect) and only ever shows `current_user`'s data
  (there is no route to view another user's — assert no `:username` param path exists); `AnalyticsPolicy`
  (self only); **k-suppression** — a hoojah with `< 5` total votes shows "fewer than 5 votes", not the
  split; totals/divisiveness computed correctly from denormalized counts; **no query joins votes→users**
  (assert the query object touches only `hujahs`); brakeman/`verify_authorized` clean.
- **System (cuprite):** signed-in user opens `/dashboard`, sees their distribution bars + totals; a
  low-vote hoojah shows the suppressed label.
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Execution model

Spec → **specialist reviews (security — the privacy gates; simplicity)** → `writing-plans` →
subagent-driven build with per-phase review gates. (Stimulus review skipped — no new controllers.)

## Risks / open questions

- **Divisiveness formula** — pick one, document; it's presentation, low-risk.
- **k threshold** — 5 for MVP; note it's tunable.
- **Existing `new_vote` rows** — backfill nulls them; confirm no other code reads `new_vote.subject_user_id`.
- **Future trends increment** — only safe now that Part A landed; still needs its own spec + a
  `rails-security-auditor` pass (day/week buckets, never split by choice, k-suppress, no per-vote times).
- **Public stats** — none in MVP; `vote_count`/`hujah_count` are already public on `UserSerializer` (out
  of scope to change here).

## Deferred (later program work)

Analytics trends (rollup + Solid Queue), reach/impressions, follower-growth analytics; Badges + Trending;
Block/mute + private accounts; debate Increments 2a/2b/3; Project 3.
