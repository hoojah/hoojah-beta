# verdict-k + unify k=3 — Design

**Date:** 2026-08-26
**Branch:** `security/verdict-k` (off `master`, isolated worktree)
**Closes:** SECURITY-FINDINGS.md `verdict-k`; adjusts the 2a/A7 threshold per owner decision
**Status:** design (owner decided 2026-08-26: k=3, hide winner below k)

## Summary

Two changes, one theme (secret-ballot k-anonymity):

1. **Lower the threshold to k=3 everywhere.** The single source is `UserAnalytics::K` (already reused
   by `Hujah::VOTE_BREAKDOWN_MIN`). Change it `5 → 3`; this propagates to hoojah vote breakdowns, the
   analytics distribution, and (new) debate verdicts. One constant, no drift.
2. **Gate debate spectator verdicts (`verdict-k`).** A concluded debate's winner-hero derives the
   **winner from the vote counts**, so at tiny N the winner itself leaks a spectator's vote. Below k,
   suppress the winner AND the split; show only the spectator total + the viewer's own verdict.

## Owner decisions (2026-08-26)

- **k = 3** for all secret-ballot surfaces (was 5). Applies to votes, analytics, verdicts.
- Below k, **hide the winner too** (not just percentages) — the winner is a function of the counts and
  leaks at N=1–2.

## Change 1 — k = 3 (single constant)

`app/models/user_analytics.rb`: `K = 5` → `K = 3`. Nothing else changes structurally —
`Hujah::VOTE_BREAKDOWN_MIN = UserAnalytics::K` and the analytics `suppressed? = total < K` already
reference it. Consequence: hoojah vote breakdowns and the analytics distribution now reveal at 3+
votes instead of 5+. This is the intended unification (a consistent secret-ballot floor).

**Spec fallout:** every boundary spec asserting the k=5 edge must move to k=3:
- `spec/models/hujah_spec.rb` — `breakdown_visible?`/`ballot_counts` (was 4→false/5→true; now 2→false/3→true).
- `spec/views/hujahs/_vote_bars_spec.rb`, `_vote_hero_spec.rb`, `_child_card_spec.rb`,
  `_user_hujah_spec.rb`, `_hujah_card_spec.rb` — any fixture straddling the boundary.
- `spec/requests/api/v1/secret_ballot_spec.rb` — sub-k / ≥k fixtures.
- `spec/requests/analytics_spec.rb` — suppressed-below / shown-at-or-above fixtures.
- `spec/models/user_analytics_spec.rb` — if it pins K or a boundary.
Update fixtures to straddle 3 (e.g. total 2 → hidden, total 3 → shown). Keep each surface's
below-k absence assertion + ≥k positive control.

## Change 2 — verdict-k gate

### Model (`app/models/debate.rb`)

Add, mirroring `Hujah#breakdown_visible?`:
```ruby
# Secret ballot for spectator verdicts: below k total verdicts the winner is derivable
# from the tiny counts (at 1 voter the "winner" IS their vote), so suppress the winner
# and the split until the electorate clears k. Reuses the shared UserAnalytics::K.
def total_verdicts
  verdict_tally.values.sum
end

def verdict_visible?
  total_verdicts >= UserAnalytics::K
end

# The signed-in viewer's own verdict choice (string) or nil — the one datum safe to show
# below k (it's their own vote), mirroring Hujah#current_user_vote.
def verdict_by(user)
  return unless user
  debate_verdicts.find_by(user_id: user.id)&.choice
end
```
`verdict_tally` / `verdict_winner` are unchanged and stay usable server-side; the VIEW decides what
to render.

### View (`app/views/debates/_verdict.html.erb`, Branch B — the concluded winner-hero)

Gate on `debate.verdict_visible?`:
- **≥ k:** render the existing winner-hero unchanged (crown, "Winner" pill, dimmed loser,
  `challenger_pct`/`opponent_pct`, result bar, "Decided by N spectators…").
- **< k:** render a suppressed hero: keep the **"Decided by N spectators over R rounds"** total
  (always safe), add a **"Final verdict sealed until K spectators have voted"** line, and show the
  viewer's own verdict if present ("Your verdict: Challenger"). Render **no** crown, "Winner" pill,
  percentages, result bar, or winner/loser dimming. Compute `winner`/percentages only inside the
  `verdict_visible?` branch so nothing derived from the split reaches the DOM below k.

Branch A (live voting buttons for an eligible, not-yet-voted spectator) is unchanged. The
`create.turbo_stream.erb` re-render inherits the gate automatically (it re-renders this partial).

## Testing

- **Model:** `total_verdicts`, `verdict_visible?` at boundaries (2 → false, 3 → true); `verdict_by`
  returns the viewer's choice / nil.
- **View (`spec/views/debates/verdict_spec.rb`):** below k (e.g. 2 verdicts) → no crown, no `%`, no
  result bar, no "Winner" pill; shows the spectator total + the "sealed" note; shows the viewer's own
  verdict when set. At ≥ k (e.g. 3 verdicts) → full winner-hero (existing assertions, fixtures moved
  to total ≥ 3). Keep the no-voter-identity assertion.
- **System (`spec/system/debate_verdict_spec.rb`):** the current test votes once (N=1) and asserts
  "100%" / "winner" — update: at N=1 (< k) it now shows the sealed note + "Your verdict", not a
  winner/percentage. Add/extend a path that reaches N=3 to assert the hero appears.
- **Model/request/policy verdict specs** unchanged except where they assert display.
- Full isolated-DB suite green; standardrb/brakeman/bundler-audit clean.

## SECURITY-FINDINGS.md

- Move `verdict-k` from OPEN to a new "Closed 2026-08-26" note with the commits.
- Note the 2a/A7 threshold lowered **5 → 3** (owner decision), unified via `UserAnalytics::K`.

## Out of scope

- No change to verdict casting, the one-vote-per-spectator unique index, or `verdict_winner`'s
  tie/draw logic. No debate serializer exists — nothing API to gate.
- The stance-tagged-replies residual-risk note (votes) does not apply to verdicts (no reply-to-verdict
  mechanism).
