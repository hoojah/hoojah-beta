# Animation improvement plans

Self-contained implementation plans produced by `improve-animations` from the
`find-animation-opportunities` survey of the whole app (2026-08-25). Each plan is written for an
executor with zero context — exact files, exact values, exact verification.

**Why these live under `docs/` and not a root `plans/`:** Tailwind v4 scans the whole repo as
source, and these plans contain literal class and keyframe names (`debate-turn-enter`, `hrise`,
`data-dialog-target`). At the repo root they would mint stray CSS rules (the `CLAUDE.md` "Tailwind
gotchas" trap). `docs/` is already `@source not`-excluded in
`app/assets/tailwind/application.css`, so plans here cannot pollute the bundle.

## Plans

| #   | Title                                              | Severity | Category                | Status |
| --- | -------------------------------------------------- | -------- | ----------------------- | ------ |
| 001 | Debate turn arrival entrance                       | MEDIUM   | Missed opportunity      | DONE   |
| 002 | Shared `<dialog>` modal scale-in                   | MEDIUM   | Missed opportunity       | DONE   |

Both applied on `master` atop `d903d72` (18 examples / 0 failures across the cited debate specs;
modal system specs green). Two human feel-checks remain (in each plan): the turn bubble rising in
over Action Cable on both participants' screens, and the three modals scaling in centered.

**Verification gotcha both plans hit and now document:** the built `app/assets/builds/tailwind.css`
is minified to a single line and Lightning CSS strips quotes from attribute selectors, so `grep -c`
(line count) under-reports. Use `grep -o '<pattern>' … | wc -l` with the **unquoted** selector
(`data-dialog-target=dialog`) instead.

## Recommended order

1. **002 first**, then **001.** They are independent and can land in either order, but 002 introduces
   the `--ease-out` custom-property token in `:root`. 001 does **not** depend on that token (it inlines
   the same `cubic-bezier` in a keyframe `animation` shorthand, where `var()` is not reliable across
   engines), so there is no hard dependency — but doing 002 first means the token exists before anyone
   is tempted to reach for it. Whichever runs first, `--ease-out` must be added exactly once; both
   plans guard against a duplicate.

## Shared context (both plans)

- All authored animation CSS lives in `app/assets/tailwind/application.css`, after the `h*` keyframes
  (lines 366–372) and the `.hrise` class (line 379). That file is **not** scanned by Tailwind, so
  comments and hand-authored rules there are safe.
- Both plans add `prefers-reduced-motion` handling (the repo currently honors it nowhere — a separate,
  pre-existing gap not addressed here).
- Commit stamp for both: `d903d72`. If code has drifted, each plan says STOP and report rather than
  improvise.

## Not planned (deliberately deferred)

From the survey, out of scope for this batch:

- **Reduced-motion for existing infinite animations** (`hbreathe` on live pills, `hboom`/`hray` bursts)
  — an existing-motion correctness fix, not a new entrance. Belongs in a fresh `improve-animations`
  audit pass.
- **Flash / toast entrance** — there is no flash/toast surface rendered anywhere (the layout `yield`
  is bare). That is a feature gap, not an animation opportunity; nothing to animate until the surface
  exists.
- **Menu (`<details>`) panel scale-in** — real but lower leverage and frequency-sensitive (tens/day);
  survey row #4. Revisit if 001/002 land well.
- Dead keyframes `hfloat` and `hbar` appear unused in `app/` — a cleanup for `improve-animations`, not
  an opportunity.
