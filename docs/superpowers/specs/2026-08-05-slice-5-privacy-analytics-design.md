# Slice 5: Vote-Privacy Hardening + User Analytics (MVP)

_Design spec. Date: 2026-08-05. Status: **design + specialist-reviewed** (security, simplicity — folded,
v2). "Land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`)._

> **Review incorporation (v2).** Part A is a **one-argument deletion** (+ backfill), not a schema change.
> **Cut `AnalyticsPolicy`** (tautological — resource is always `current_user`): use `authenticate_user!` +
> `skip_authorization`, owner-only by construction. **Defer the divisive/consensus ranking** (simplicity
> scope-cut; also removes the security ranking-selection-leak). Bars are **Tailwind width-% divs** (copy
> `_vote_bars`' idiom, not SVG; don't share the interactive partial). Plain `UserAnalytics` PORO at
> `app/models/`. **Honest reframe (security 2a):** per-hoojah counts are ALREADY public+unsuppressed at any
> N on hoojah cards — the dashboard's k-gate does not close a secret-ballot gap; it only stops the
> dashboard being an efficient discovery index and future-proofs the trends increment.

## Context

Shipped: feed/voting/arguments/compose/profile/notifications/flags/share, Devise, Pundit, Slice 3 social,
Slice 4 debate. This slice (A) closes a vote-privacy leak in notifications, then (B) ships an owner-only
analytics dashboard built so it can never re-open that leak.

## Part A — Vote-privacy hardening (do first)

**The leak:** `Hujah#cast_vote` (`app/models/hujah.rb:55`) sets `subject_user_id: by.id` on the `new_vote`
notification, and `NotificationSerializer` exposes `subject_user.username` — so `Api::V1::NotificationsController#index`
hands a hoojah **owner the username (+ notification timestamp) of everyone who first-voted** on their
hoojah (choice stays secret). Votes are an effectively secret ballot; this identity+timestamp seam is the
top de-anonymization vector.

**Fix (source, minimal):**
1. **Delete the single argument `, subject_user_id: by.id`** from the `new_vote` `Notification.create!` in
   `cast_vote`. The column stays (load-bearing for `new_hoojah_response`/`mention`/`new_follower`/`debate_*`,
   which name legitimately *public* actors); it just goes unset for `new_vote` (defaults nil via
   `optional: true`). The HTML card already shows "you have a new vote" with no username (confirmed); the
   serializer's `if notification.subject_user_id` guard then emits no `subject_user` for `new_vote`.
2. **Backfill (data-only migration):** `Notification.where(category: :new_vote).update_all(subject_user_id: nil)`
   — this is the actual remediation for existing rows.
3. **Accepted residual (Risks):** the `new_vote` notification's own `created_at` still tells the owner *a*
   vote landed *and when* (not who). Inherent to any activity-notification; accepted trade-off, documented.

## Part B — User Analytics dashboard (MVP)

### Goal & honest threat model

An **owner-only** `/dashboard` where a user sees their own content's aggregate performance. It shows only
aggregate counts of the **owner's own hoojahs** — data that is **already public** on the hoojah cards, and
never contains per-voter identity. So once Part A lands, the MVP dashboard introduces **no new
de-anonymization vector**: the owner views their own already-public aggregates; individual votes are never
joined to users anywhere.

### Metrics (MVP — from `hujahs` denormalized counts only)

- Per-hoojah vote distribution (agree/neutral/disagree + %) for the owner's top-level hoojahs.
- Totals: votes received (`SUM(agree+neutral+disagree)` over own hoojahs), arguments received (count of
  child hoojahs whose parent is the owner's).
- **Deferred:** "most divisive / most consensus" ranking (scope creep + a tunable-formula rabbit hole +
  the k-filter-before-selection subtlety) → the later trends increment.

### Privacy gates (owner-only + future-proofing; honestly scoped)

1. **Owner-only.** `/dashboard` → `AnalyticsController#show`, always `current_user` (no username in the
   URL, like `/notifications`). `before_action :authenticate_user!` + `skip_authorization`. No
   `AnalyticsPolicy` (it would be tautological — the resource is always `current_user`; owner-only holds
   because the query is `Hujah.where(user_id: current_user.id)` and no other-user route exists).
2. **No surface ever joins `votes → users`.** No `VoteSerializer`, no votes-list, no per-voter data — MVP
   reads only aggregate counts off `hujahs`. Encoded as a rule + a test asserting the query object touches
   only `hujahs`.
3. **k = 5 suppression (defense-in-depth / future-proofing, in the PORO).** A per-hoojah split with total
   votes `< 5` renders "fewer than 5 votes" instead of the split, computed once in `UserAnalytics`.
   **Honest note:** this does NOT close a live gap for MVP — the same per-hoojah counts are already public,
   unsuppressed, at any N on the hoojah card/show page (security finding 2a). Its value is (a) stopping the
   dashboard from being an efficient discovery index over the owner's many hoojahs, and (b) making the
   `UserAnalytics` suppression pattern already correct for the trends increment (where exposure won't be
   redundant with a public page). Keep it; don't overclaim it.
4. **No per-vote timestamps / no time series** in MVP (the gated trends increment).
5. **API discipline:** no JSON analytics endpoint in MVP. If added later it reuses this owner-only scoping,
   never accepts a `:username`, aggregate-only.

### Architecture

- **Compute-on-read, zero new tables.** A plain PORO `app/models/user_analytics.rb` — `UserAnalytics.new(current_user)`,
  ordinary reader methods (`totals`, `distributions`) — runs grouped SQL over `Hujah.where(user_id:
  current_user.id)` off the denormalized counts (one query, no votes scan, no N+1) and owns the k=5
  suppression. No base class, no `app/queries/` dir.
- **UI:** `GET /dashboard` (`AnalyticsController#show`, thin). **Tailwind width-% div bars** (copy the ~3
  lines of bar markup from `_vote_bars` into a read-only `_distribution_bar`; do NOT share the interactive
  `_vote_bars` partial — it's welded to a `button_to` vote form). No SVG, no chart lib, no JS, no per-panel
  lazy frames (the whole page is 2–3 grouped queries — render in one pass). Navbar "Dashboard" link for
  signed-in users.

### Component boundaries

`AnalyticsController#show` (thin); `UserAnalytics` PORO (aggregates + k=5); views `analytics/show` +
`_distribution_bar` + `_stat`. No policy, no Stimulus, no gems.

## Testing

- **Part A:** `cast_vote` → `new_vote` notification has `subject_user_id == nil`; the API notifications
  serializer returns no `subject_user` for a `new_vote`; other categories still carry it; the backfill nulls
  existing `new_vote` rows.
- **Part B:** `/dashboard` requires login (unauth → redirect); shows only `current_user`'s data (assert no
  `:username`/other-user route path exists); totals computed correctly from denormalized counts;
  **k-suppression** — a hoojah with `< 5` total votes shows "fewer than 5 votes", not the split; **assert
  the query object touches only `hujahs`** (no votes/users join); brakeman/`verify_authorized` clean.
- **System (cuprite):** signed-in user opens `/dashboard`, sees distribution bars + totals; a low-vote
  hoojah shows the suppressed label.
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Execution model

This reviewed spec → `writing-plans` → subagent-driven build with per-phase review gates. (Stimulus review
skipped — no new controllers.)

## Risks / open questions

- **[Tracked follow-up, out of scope] Public per-hoojah counts (security 2a):** `agree/neutral/disagree`
  counts + % are already rendered publicly at any N (incl. N=1) on hoojah cards/show pages to anonymous
  visitors — the app's largest actual "secret ballot" gap, independent of this slice. Closing it needs
  product-level rounding/suppression on public pages (a much bigger change). Track separately; the future
  trends increment must be reviewed against this same baseline.
- **Residual `new_vote` timestamp leak** (Part A) — accepted trade-off (activity notifications inherently
  reveal timing, not identity).
- **Trends increment** (later) — only safe now that Part A landed; still needs its own spec + a
  `rails-security-auditor` pass (day/week buckets, never split by choice, k-filter *before* any ranking
  selection, no per-vote times), and must inherit the 2a public-card caveat.

## Deferred (later program work)

Analytics trends (rollup + Solid Queue) + divisive/consensus ranking, reach/impressions, follower-growth;
Badges + Trending; Block/mute + private accounts; debate Increments 2a/2b/3; Project 3.
