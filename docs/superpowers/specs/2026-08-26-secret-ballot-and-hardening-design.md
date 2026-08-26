# Secret-Ballot k-Anonymity + Security Hardening — Design

**Date:** 2026-08-26
**Branch:** `security/secret-ballot-and-hardening` (off `master`, isolated worktree)
**Closes:** SECURITY-FINDINGS.md items **2a**, **A7**, **vote?-block**, **notif-param-500**, **username-uniq-index**
**Status:** design (owner already decided 2a = option C, k=5)

## Summary

Two threads:

- **Secret-ballot k-anonymity (2a + A7):** a hoojah's per-stance vote **breakdown**
  (agree/neutral/disagree counts + percentages) is hidden while the electorate is small enough to
  de-anonymize an individual voter. Threshold **k = 5 total votes** (owner decision 2026-08-19,
  option C). Below k: show the **total** vote count and the **viewer's own stance**, but no
  breakdown. At ≥ k: show the full split as today. Applies to every HTML surface **and**
  `HujahSerializer`, plus the analytics distribution (A7).
- **Three low-severity hardening fixes:** `HujahPolicy#vote?` block check, the API notifications
  param 500, and a `users.username` unique index.

## Threat model (why 2a)

Vote tallies are denormalized counters and votes are an effectively **secret ballot** — the
`new_vote` notification already deliberately omits `subject_user_id` (`Hujah#cast_vote`) so the
owner cannot de-anonymize voters. But the **published per-stance breakdown** re-opens the same
leak by counting: on a hoojah with 2 votes, the breakdown "1 agree / 1 disagree" combined with
knowing one voter's stance reveals the other's. Below a small k, the breakdown itself is the leak.

## Core rule (single source of truth on the model)

Add to `Hujah` (`app/models/hujah.rb`):

```ruby
# Secret ballot: hide the per-stance breakdown until the electorate is large enough
# that the published split can't be used to de-anonymize an individual voter.
# Below this many total votes, surfaces show the total + the viewer's own stance only.
# Reuses UserAnalytics::K (already 5) as the single threshold source so the analytics
# suppression and this cannot drift apart.
VOTE_BREAKDOWN_MIN = UserAnalytics::K

# Total votes cast across all three stances (the electorate size). Replaces the
# `agree_count + neutral_count + disagree_count` sum duplicated across views/model.
def total_votes
  agree_count.to_i + neutral_count.to_i + disagree_count.to_i
end

# Whether the per-stance breakdown may be shown. Uniform for everyone — including the
# author (the secret-ballot threat treats the author as an observer too).
def breakdown_visible?
  total_votes >= VOTE_BREAKDOWN_MIN
end
```

> **Existing precedent.** `UserAnalytics::K = 5` + `#suppressed?` already implement this exact
> k-suppression for the analytics distribution. Reuse `UserAnalytics::K` here rather than minting a
> second `5` (Fable leak-audit finding 3). Confirm `UserAnalytics::K == 5` at implementation.

**No author exception.** The author is as able to de-anonymize as anyone, and the existing
secret-ballot precedent (the id-less `new_vote` notification) already refuses the author that power.

## HTML surfaces

Every surface that renders a per-stance count or percentage gates on `hujah.breakdown_visible?`.
When false, it renders a compact **"N votes"** total (0 → "No votes yet") and preserves the
viewer's-own-stance affordance; it does **not** render per-stance widths, percentages, or counts.
The vote **buttons** (and the `voted`/pressed highlight of the viewer's own stance) always render —
you can still vote on a sub-k hoojah; you just don't see the split.

Files:

- `app/views/hujahs/_vote_bars.html.erb` — feed-card segmented bar + percent legend. Below k: replace
  the bar + legend with the total; keep the three vote buttons + `voted` highlight.
- `app/views/hujahs/_vote_hero.html.erb` — single-hoojah widget. Below k: replace per-stance
  pct/count rows + segmented bar with the total; keep buttons + `voted` highlight. `conviction_count`
  is **not** a per-stance breakdown (it's a single aggregate) and is left as-is.
- `app/views/hujahs/_child_card.html.erb` (inline reply counts) — below k: total only.
- `app/views/users/_user_hujah.html.erb` (profile card per-stance counts) — below k: total only.
- Surfaces that already show only a **total** (`_hujah_card.html.erb:68`, `show.html.erb:18/24`,
  `_trending_rich.html.erb`) are unaffected — but switch their inline
  `agree_count + neutral_count + disagree_count` sums to `hujah.total_votes` for DRY-ness.

## HujahSerializer (A7 — the API leg)

`app/serializers/hujah_serializer.rb`. The owner already accepted **breaking** `Api::V1` contract
changes (Slice 11 note: no legacy native client in production). Change:

- Add an always-present `total_count` attribute = `hujah.total_votes`.
- `agree_count` / `neutral_count` / `disagree_count` return `nil` when
  `!hujah.breakdown_visible?`, else the real value. Same treatment for the nested `children` counts.
- `current_user_vote` (viewer's own stance) is unchanged — it's the viewer's own datum, not a leak.

So a sub-k hoojah serializes as `{total_count: 3, agree_count: null, neutral_count: null,
disagree_count: null, current_user_vote: "agree", ...}`.

### UserSerializer#hujahs — the second API leak (Fable finding 1)

`app/serializers/user_serializer.rb` (the `hujahs` attribute, ~lines 27-29) serializes
`agree_count`/`neutral_count`/`disagree_count` for **every visible hoojah of a user**, served by
`GET /api/v1/users/:username`. This is the exact data being gated, reachable by profile lookup —
so it must be gated identically: per child hoojah, nil the three counts when
`!hujah.breakdown_visible?` and add `total_count: hujah.total_votes`. (Mirror whatever helper
`HujahSerializer` uses so the two stay consistent.)

## Analytics distribution (A7 — aggregate leg) — ALREADY IMPLEMENTED

The author's aggregate received-vote distribution (`app/views/analytics/_distribution_bar.html.erb`,
`UserAnalytics`) **already suppresses** its per-stance split below k via `UserAnalytics::K = 5` and
`#suppressed?` (Fable finding 9). **No new work here — verify only** with a spec that the analytics
distribution hides the breakdown below k and shows it at ≥ k (add if not already covered).

## Hardening fixes (independent, no design ambiguity)

1. **vote?-block** — `app/policies/hujah_policy.rb#vote?`: add the same block check `#create?` has, so
   a blocker cannot vote on a blocked author's public hoojah:
   ```ruby
   def vote?
     user.present? && record.visible_to?(user) &&
       !user.hidden_user_ids.include?(record.user_id)
   end
   ```
   (`hidden_user_ids` is bidirectional, so this also stops voting on a blocked-by author.)
2. **notif-param-500** — `app/controllers/api/v1/notifications_controller.rb#notification_params`:
   `params[:notification].permit(:read)` → `params.require(:notification).permit(:read)`, mirroring
   `FlagsController#flag_params`. `Api::V1::BaseController` already rescues `ParameterMissing`? — if
   not, add a scoped `rescue_from ActionController::ParameterMissing` → `:bad_request` mirroring
   `Api::V1::FlagsController` (the test env runs `show_exceptions = :none`, so an unrescued raise is a
   500 in the spec). Result: a PATCH with no `notification` key → **400**, not 500.
3. **username-uniq-index** — migration adding a unique index on `users.username`:
   ```ruby
   class AddUniqueIndexToUsersUsername < ActiveRecord::Migration[8.1]
     disable_ddl_transaction!
     def change
       add_index :users, :username, unique: true, algorithm: :concurrently
     end
   end
   ```
   Closes the check-then-act race in `User.generate_username` (OAuth). **Deploy note:** a concurrent
   unique-index build aborts if duplicate usernames already exist in prod — the deploy must confirm
   `SELECT username, count(*) FROM users GROUP BY username HAVING count(*) > 1` is empty first. (Dev/test
   have none.) Keep the `strong_migrations` concurrent form.

## Testing

- **Model:** `total_votes`, `breakdown_visible?` at boundaries (4 → false, 5 → true, 0 → false).
- **Views:** `_vote_bars` / `_vote_hero` — below k render total + buttons, no percentages/per-stance
  counts; at ≥ k render the split (extend existing `spec/views/hujahs/_vote_bars_spec.rb`,
  `_hujah_card_spec.rb` whose fixtures already use total 100). `_child_card`, `_user_hujah` similarly.
- **Serializer/request:** `spec/requests/api/v1/...` — sub-k hoojah has null breakdown + `total_count`;
  ≥ k has real counts; `current_user_vote` always present.
- **Analytics:** below-aggregate-k hides the distribution.
- **Hardening:** policy spec (blocker cannot `vote?`); request spec (PATCH notification with no key →
  400); model/DB spec that the unique index rejects a duplicate username; migration applies.
- Full `bin/ci`-equivalent (isolated DB) green before merge.

## Out of scope / notes

- Percentages are derived from counts, so hiding counts must also hide percentages (same gate) — a
  percentage is a normalized count and leaks identically at small k.
- No change to `cast_vote`, the vote model, or the vote→reply gate.
- The `conviction_count` aggregate is not a per-stance breakdown and stays visible.
- Trending's internal score still uses real counts server-side (never rendered) — unaffected.

### Explicitly OUT OF SCOPE (recorded as a new finding, not built here)

- **Debate spectator-verdict percentages** (`app/views/debates/_verdict.html.erb`,
  `Debate#verdict_tally`) render with no k floor and are the *same class* of secret-ballot leak, but a
  **different electorate** (verdict votes, not hoojah stance votes) with no owner k-decision. Finding
  2a is specifically hoojah vote counts. This will be **logged as a new tracked finding** in
  `SECURITY-FINDINGS.md` (`verdict-k`), not fixed in this pass — it needs its own owner decision.

### Accepted residual risk (documented, not fixed)

- **Stance-tagged public replies shrink the effective anonymity set** (Fable finding 5). Replying
  requires a prior vote and a child hoojah publicly carries its author's stance, so voters who also
  replied have *voluntarily* disclosed their stance. At total = k with k−1 stance-tagged repliers, the
  newly-revealed split pins the last voter. Effective k = `total_votes − publicly-stance-tagged
  voters`. Repliers self-disclosed; the residual exposure of the one silent voter at exactly the
  boundary is an **accepted** limitation of a count-threshold rule — closing it fully needs a
  reply-aware threshold, deferred. Recorded in `SECURITY-FINDINGS.md`.
