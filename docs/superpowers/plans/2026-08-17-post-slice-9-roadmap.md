# Post-Slice-9 Roadmap — what ships next, and why

_Written 2026-08-17 against `master` @ `f7bdc23`. Suite 530 / 0 / 0; brakeman 0; standardrb clean;
bundler-audit clean; working tree clean, **not pushed**._

Read `HANDOVER.md` first — this file only decides sequence. The reasoning behind each deferral lives
there and in `SECURITY-FINDINGS.md`.

---

## Do this first

**Slice 10 (CI) starts immediately**, and two owner decisions get asked in parallel while it runs:

1. **The secret-ballot public-counts question** (Slice 13 below). It gates that slice's shape and
   nothing else, but it must be *decided* before real traffic — votes cast under one privacy regime
   cannot be retroactively re-anonymized in users' minds.
2. **Does any legacy native/mobile client still hit `Api::V1` in production?** Every API-contract call
   below assumes **no**. If the answer is yes, Slice 12's wire-format change becomes additive behind a
   serializer shim; the ordering still holds.

**Project 3 (Hotwire Native) is NOT next. It is fourth.** The HANDOVER has said "before Project 3"
about the same three items since Slice 1 (`rack-cors`, `require_master_key`, `Api::V1` parity), and
the post-Slice-9 passes added two more reasons: the API's stance wire format is about to change, and
there is no CI to catch what a native shell repo cannot see. Native clients bake contracts in.
Everything that changes the contract or hardens the surface goes first — and each preceding slice
ships standalone value rather than merely clearing the runway.

---

## Slice 10 — CI: green by enforcement, not convention — **S**

**Goal:** every gate that has been green by hand becomes a merge-blocking check.

- `bin/ci` — one script running the canonical gates in order: `standardrb`, `brakeman -q`,
  `bundler-audit check --update`, `bin/rails db:test:prepare`, then the full suite with
  `RUBYOPT='-W0'` including system specs.
- `.github/workflows/ci.yml` — **the remote is GitHub**, so Actions is right and no migration is
  needed. Postgres service container, mise/Ruby setup, Chrome for Cuprite (`CUPRITE_CHROME_PATH`),
  and **every step run from the repo root** — Slice 9 established that `@source not` paths resolve
  relative to the working directory, so a Tailwind build from anywhere else silently re-admits
  `docs/` and `spec/` to the safelist.
- Wire **prosopite** in dev/test as **logging only, not raising** — the N+1 audit deferred since
  Slice 2 becomes ambient observation instead of its own slice.
- Ledger housekeeping: mark the historically-closed `SECURITY-FINDINGS.md` rows (C1–C5, H1, H4, H6,
  M4, M6, M7, L3 — all resolved during Project 2 and confirmed by the 2026-08-17 audit's "no
  Critical/High") as closed with commit references, so the genuinely open set is legible: M1, L4,
  `flag_params`, API parity, 2a.

**Why here:** cheapest item on the board, and it multiplies the safety of every slice after it. This
session's own evidence is the argument — a fixed-window rate-limit flake that **three consecutive
green runs missed**. Convention is not detection.

**Note on the shared-DB constraint:** "all agents share one Postgres test database" is a *local*
constraint. CI gets its own service container per run, and becomes the serialization point that
constraint has been missing.

**Main risk:** system specs flaking on CI hardware — Chrome timing differs from this Mac. Mitigation:
run system specs as a separate non-blocking job for the first week, promote once stable.

---

## Slice 11 — API hardening: the pre-native, pre-traffic surface — **M**

**Goal:** `Api::V1` reads enforce the same block/private-account graph the HTML surface does, and the
three "before Project 3" flags close.

- **`Api::V1` read parity** — the substantive item. Feed/children/user endpoints filter
  `hidden_user_ids`; private-visibility parity in `HujahSerializer#children`/`parent` and the
  notifications endpoint. Slice 7b hardened the top-level index/show/user endpoints but explicitly
  deferred serializer-nested content, so **a private author's reply is reachable today through a
  public hujah's API children.** That is a real leak with live-traffic exposure, not just native prep
  — the one open item that is both a before-traffic and a before-native requirement.
- **`rack-cors`: delete the config outright.** Re-triaged to Low on 2026-08-17 — dead config from the
  retired React dev server, and native clients are not CORS-gated so it protects nothing either way.
  Deleting beats ENV-driving because there is no cross-origin browser consumer any more.
- **`flag_params` contract decision: adopt `require`**, matching the HTML sibling — 400 on a missing
  `flag` key instead of the current 500. This *is* the contract decision the audit deferred, and the
  right moment to make it is the last one before a native client exists.
- **`require_master_key` (L4) rides the deploy track**, not this slice — it is gated on the deploy
  providing the key, not on code.

**Why here:** closes the only open security item with live-traffic exposure, and freezes the API's
*authorization* semantics before Slice 12 changes its *value* semantics and Project 3 consumes both.

**Main risk:** parity filtering inside serializers can N+1 on per-child visibility checks. Reuse the
Slice 7b `@children` SQL predicate (`users.private = false OR user_id IN (...)`); prosopite from
Slice 10 is now watching.

---

## Slice 12 — Stance domain unification: array→scalar, then enum — **M**

**Goal:** one stance domain, one representation.

**Ruling on one-slice-vs-two: ONE slice, strictly ordered inside it.** Both items touch the same
call-site family (`cast_vote`, `current_user_vote`, `Hujah::STANCES`, `HujahSerializer`, the vote
views), so two slices pays the implementer→review→re-verify overhead twice on the same files. And the
order is forced: **an array column cannot be enum'd**, so the collapse must precede the enum.

**Task 1 — array→scalar** (the Slice-1 deferral; yes, worth doing). Add a scalar `stance` column,
batched backfill from the array's last element under the `strong_migrations` treatment,
`ignored_columns` transition, swap `cast_vote` (append → assign) and `current_user_vote`
(`.vote.last` → `.stance`), drop the array in a follow-up migration. **What breaks:** the vote
change-history is discarded — acceptable, since nothing reads anything but `.last` and the roadmap
already ruled it stays un-serialized. Record that in the migration comment. This also removes the
strangest write on the app's hottest write path.

**Task 2 — enum the trio + the new scalar in ONE commit.** `hujahs.vote`,
`debates.challenger_stance`, `debates.opponent_stance` and `Vote#stance`, all together, exactly as the
recorded hazard demands: enum-ing `Hujah#vote` alone flips its reader from `1` to `"agree"`, which
lands in a non-enum `opponent_stance:` and **coerces to 0** — silent data corruption. The same commit
updates every `.vote` reader (views, `HujahSerializer`, and the `STANCES`/`COUNTER_FOR` pair
collapsing into the enum), plus a backfill audit for out-of-domain values — `Debate` currently
"cannot distinguish a real stance from a `7`".

**Why here — before native, after hardening:** enums flip serializer output from `1` to `"agree"`, an
API wire-format change. With no native client and the SPA retired, the contract can change cheaply
**once**, now. After Project 3 it cannot.

**Main risk:** the coercion hazard itself, plus a wide mechanical diff. Mitigations: the atomic-commit
rule, CI from Slice 10, and a pre-flight spec asserting no cross-model raw-integer stance hop remains
(`DebatesController#create` is the known site).

---

## Slice 13 — Secret-ballot public counts (finding 2a) — **S**, gated on an owner decision

**Goal:** close, or explicitly accept, the largest recorded secret-ballot gap — per-hoojah
agree/neutral/disagree counts are public and unsuppressed at any N, which `/dashboard`'s k=5
suppression does not touch.

This is a **product decision first.** Three options, framed rather than assumed:

- **A — accept and document.** Public results are arguably the product: Hoojah is a poll plus the
  arguments behind it. The real leak is only at low N (one vote, plus the `new_vote` notification
  timestamp, lets an owner infer an individual's stance). At beta scale, blanket k=5 suppression
  would blank most cards and kill the feedback loop that makes a young platform feel alive.
- **B — k=5 suppression on public surfaces**, mirroring `/dashboard`: below 5 votes show the total and
  "not enough votes yet", no per-stance split. Consistent, small, strongest privacy posture.
- **C — the middle path (recommended).** Below k=5 show the total *and the viewer's own stance* but no
  breakdown; at ≥5 show the full split. Preserves the voting feedback loop while closing the low-N
  inference vector, at the same size as B.

**Why here:** must be decided before real traffic; the implementation is small and independent, so it
slots after the two contract-freezing slices and before native bakes the vote-display contract into a
shell. **If the owner picks A, this slice collapses to a paragraph in `FEATURES.md` — that is a fine
outcome; the deliverable is the decision on the record.**

**Main risk:** none technical. The risk is *skipping* the decision and letting Project 3 encode
today's behaviour by default.

---

## Slice 14+ — Project 3: Hotwire Native — **L** (its own brainstorm → spec → plan cycle)

**Rails side first**, all shippable and testable against the web app alone: path-configuration
endpoint, native-app detection in layouts (hide web chrome), native auth flow. Then the separate shell
repo(s). Because Hotwire Native wraps the server-rendered views, most of the product comes for free;
`Api::V1`'s role is native-specific surfaces — which is exactly why Slices 11–12 froze it first. The
deep-link-friendly URLs (`/u/:username`, `/debates/:slug`, `/dashboard`) were designed for this.

Also on this slice's checklist from the backlog: `app-icon-512.png` fetch, and the
`pinned-tab.svg`/favicon repair (the mirrored asset is a degenerate potrace output — a filled black
rectangle — and would render as a black square in Safari's tab strip).

**Main risk:** the first work outside this repo's harness — CI, specs and the review method do not
cover a Swift/Kotlin shell. The Rails-side/shell split contains that; the Rails half stays under the
house method.

---

## Parallel owner track — deploy readiness (mostly not code)

`config/deploy.yml` is still placeholders (`my-user/hoojah`, `app.example.com`), so whatever serves
beta.hoojah.my today is **not** deployed from this repo's Kamal config. Before "real traffic" means
anything: real registry/host values, `RAILS_MASTER_KEY` + `APP_HOST` + DB env, the Solid* production
databases created, `assets:precompile` in the deploy (the Tailwind bundle is gitignored), **enable
`config.require_master_key` — this closes L4**, and communicate the known one-time logout from the
7.0 session-key change. Owner-supplied values plus an S-sized verification pass; can run alongside
Slices 10–11.

---

## Deliberately not doing

- **Analytics trends / divisive-consensus ranking** — deferred for a real reason (formula rabbit hole
  plus a k-filter-before-selection subtlety) and gated on there being traffic to analyze.
- **`debate_won` badge / changeable verdict / live verdict-tally broadcast** — all blocked on the same
  unresolved question: when is a verdict tally *final*? Slice 8 recorded it; nothing has changed it.
- **Bookmarks, identity verification** — roadmap-optional and roadmap-out-of-depth respectively.
- **`/follow_requests` inbox page** — the one deferred item that is a genuine UX hole (requests are
  manageable only from notification cards), but it is polish. Ride it on Slice 13 or the Project 3
  Rails-side slice, not its own slice.
- **Reversing any recorded deliberate decision.** `DebatePolicy#extend?` stays un-aliased (silent
  narrowing is the worst policy failure mode); `new_vote` stays unfiltered by blocks (anonymous, no
  vector); in-progress blocked-pair debates stay grandfathered; the section-head idiom stays
  un-unified. Each has recorded reasoning that holds.
- **ERB housekeeping** — `_distribution_bar`'s dead block arg, the `logged_in:` keyword removal,
  `focus({preventScroll: true})`, the nine phantom CSS rules. Churn-sized: sweep opportunistically
  inside whichever slice already touches the file, never as standalone work.

---

## What would change this ordering

- **A confirmed live legacy API client** → Slice 12's wire-format change becomes shimmed/additive
  rather than breaking.
- **Real traffic arriving before CI lands** → swap 10 ↔ 11; the private-content API leak outranks
  enforcement.
- **The owner declaring native the business priority regardless** → Slices 11 and 12 compress into one
  pre-native hardening slice, with 13 riding behind. Worth arguing against: that compression is
  exactly how the Slice-2 Pundit migration left the API flags bug behind for eight slices.
