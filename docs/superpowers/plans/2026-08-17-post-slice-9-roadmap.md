# Post-Slice-9 Roadmap — what ships next, and why

_Written 2026-08-17 against `master` @ `f7bdc23`. Suite 530 / 0 / 0; brakeman 0; standardrb clean;
bundler-audit clean; working tree clean, **not pushed**._

Read `HANDOVER.md` first — this file only decides sequence. The reasoning behind each deferral lives
there and in `SECURITY-FINDINGS.md`.

---

## Do this first

**Slice 10 (CI) is ✅ DONE** — merged as PR #1 (`7e3a99f`) on 2026-08-22. Both jobs green: gates in
4m40s, system specs 33/0 in 1m30s. Its first act was to find a real latent defect (see that section).

**Slice 10b (Coolify deploy readiness) is ✅ DONE** — merged as PR #2 (`daeab4a`) on 2026-08-22, CI
green. It led with a P0 (the app could not boot in production at all) and turned up two more real
problems on the way; see that section.

**Next up is Slice 11 (API hardening).** The one open item with live-traffic exposure is there.

Both gating owner decisions are **answered** (2026-08-19), so nothing in this plan is blocked:

1. ~~**The secret-ballot public-counts question**~~ — **ANSWERED: option C**, the middle path. Below
   k=5, show the total and the viewer's own stance but no breakdown; at ≥5 show the full split.
   Applies to the HTML surfaces **and** `HujahSerializer`. Full shape in Slice 13 below.
2. ~~**Does any legacy native/mobile client still hit `Api::V1` in production?**~~
   **ANSWERED 2026-08-19 by the owner: no legacy client hits `Api::V1` in production.**
   So the API-contract changes in this plan proceed as **breaking, not additive** — Slice 12's
   stance enum may change the wire format from `1` to `"agree"` outright, and Slice 11's
   `flag_params` `require` may change a malformed request's answer from 500 to 400, with no
   serializer shim and no deprecation window. This is the cheap moment to spend that budget: the
   React SPA is retired and no native client exists yet. **After Project 3 ships, it is gone.**

**Project 3 (Hotwire Native) is NOT next. It is fourth.** The HANDOVER has said "before Project 3"
about the same three items since Slice 1 (`rack-cors`, `require_master_key`, `Api::V1` parity), and
the post-Slice-9 passes added two more reasons: the API's stance wire format is about to change, and
there is no CI to catch what a native shell repo cannot see. Native clients bake contracts in.
Everything that changes the contract or hardens the surface goes first — and each preceding slice
ships standalone value rather than merely clearing the runway.

---

## Slice 10 — CI: green by enforcement, not convention — **S** — ✅ DONE (PR #1, `7e3a99f`)

**Goal:** every gate that has been green by hand becomes a merge-blocking check.

> **What it found on day one.** CI's first run failed the system-spec job, and the cause was not CI.
> `driven_by :cuprite` does not merely select a registered driver — Rails'
> `ActionDispatch::SystemTesting::Driver` lists `:cuprite` as registerable alongside `:selenium`, so it
> **re-registers** the name with its own options and discards everything
> `Capybara.register_driver(:cuprite)` set. Measured before/after by reading the live driver's options
> inside a `js: true` example: `process_timeout` nil→20, `timeout` nil→15, `url_blacklist` 0→5 entries,
> and `--no-sandbox` absent→present. So the browser path, both timeouts, the window size and the whole
> Drift/Cloudinary blacklist had been **dead for the life of the suite** — invisible on macOS, fatal on
> Linux, where Chrome cannot start without the sandbox flag. `spec/system/cuprite_driver_spec.rb` now
> guards it. Two corollaries worth remembering: the `url_blacklist` that Slice 2's comments credit with
> fixing intermittent `Ferrum::PendingConnectionsError` **has never been in effect** (the layout guard
> skipping those scripts in test was doing all the work), and the suite **could not pass on a clean
> checkout** because nothing rebuilt the gitignored Tailwind bundle before RSpec.
>
> Two things now on a clock, both dated in the YAML: the system job's `continue-on-error: true`
> (target 2026-08-29 — a permanently non-blocking check is worse than none because it looks like one),
> and prosopite's **146 N+1 reports**, concentrated in `debate.rb:213/220/221`, `debate_policy.rb:8`,
> `hujahs_controller.rb:66`.

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

## Slice 10b — Coolify deploy readiness — **M** — ✅ DONE (PR #2, `daeab4a`)

**Goal:** the app builds, boots and serves on Coolify. Supersedes the "parallel owner track" below,
which was written around Kamal.

> ### What shipped, and two problems found on the way
>
> All seven items below landed. `bin/ci` → **536 / 0 / 0**, brakeman 0, and the image **built and ran**
> locally: container reports `healthy`, `/` returns 200 with a real DB round-trip, `bin/jobs` starts
> the Solid Queue supervisor from the same image. The `/up` host-authorization exclusion was proved
> with a control — `Host: 10.42.0.7` gets **200 on `/up` and 403 on `/`** with the exclusion, and
> **403 on `/up`** without it. `force_ssl` turned out **not** to need an `ssl_options` exclusion:
> `assume_ssl` marks every request HTTPS unconditionally, so it never redirects in this deployment,
> and adding one would have been dead config.
>
> **The database collapse needed far more than repointing URLs, and the failure mode was silent.**
> `db/{cache,queue,cable}_migrate` did not exist — only schema *dumps*. Rails loads a config's dump
> only when `schema_migrations` is absent from the target database, so once all four share one
> database the primary creates that table first and the other three are **skipped without error** —
> the app would have deployed with **zero `solid_*` tables**. The dumps are now real migrations at the
> paths `database.yml` already declared, with `force: :cascade` removed: that is a dump artifact which
> would drop populated tables, **including enqueued jobs**, on any re-run.
>
> **`db/seeds.rb` would have created live accounts with a published password.** It creates
> login-capable users sharing `PASSWORD = "1234567890"`, including the official `@hoojahhq` handle —
> and `db:prepare` runs seeds whenever it initializes a database, which is the most obvious first
> command on a fresh deploy. Now guarded with an `abort` in production, with a seed-free bootstrap
> (`db:schema:load:primary` + `db:migrate`) documented in the README. This is why
> `bin/docker-entrypoint` deliberately does **not** run `db:prepare`, unlike Rails 8's generated
> entrypoint.
>
> **Thruster over plain Puma**, but not for the reason first assumed. The initial rationale — "Thruster
> serves `public/` so `RAILS_SERVE_STATIC_FILES` can't be forgotten" — was measured and found false:
> Thruster proxies *then* caches, so with `public_file_server.enabled` false it faithfully cached a
> **404** for the stylesheet. It stays for gzip, an HTTP cache and X-Sendfile off Puma's threads, and
> the env var is baked into the image instead.
>
> ### ⚠️ Still blocking the first real deploy — owner actions
>
> - **`config/master.key` does not exist** anywhere — not locally. `credentials.yml.enc` is committed
>   and useless without it, so the key must be recovered or the credentials regenerated.
>   `RAILS_MASTER_KEY` is required env, so this blocks deploy. Enabling
>   `config.require_master_key` (**ledger L4**) is the last step of the first successful deploy.
> - **`Gemfile.lock` has `x86_64-linux` but not `aarch64-linux`.** The image was built under QEMU on
>   Apple Silicon. If Coolify runs on ARM the build cannot resolve platform gems — fix with a
>   committed `bundle lock --add-platform aarch64-linux`.
>
> ### What remains unproven until a real instance exists
>
> A Dockerfile that builds locally is not evidence Coolify runs it. Untested: that Coolify picks the
> Dockerfile over Nixpacks and maps `PORT` as assumed; a managed-Postgres `DATABASE_URL` with TLS
> params and role permissions (the collapsed layout needs CREATE TABLE on the one database); the
> amd64 image on real amd64 hardware; the worker as a separate managed service; and — **watch this
> one first** — **Action Cable's WebSocket upgrade through Coolify's proxy**, which is untested
> entirely and drives real-time debate turns. It is the most likely first-deploy surprise now that
> CSS is covered.

**The deploy target is Coolify**, not Kamal (owner, 2026-08-22). That changes the work: Coolify builds
from git (Dockerfile or Nixpacks) and fronts containers with its own proxy, so `config/deploy.yml` is
now **dead config, not placeholders to fill in**.

### ⚠️ P0 — the app cannot boot in production today

Found 2026-08-22 while probing this slice, and it is not a Coolify problem — it is a repo problem
Coolify will hit on its first build:

```
$ RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
NameError: uninitialized constant StrongMigrations
  config/initializers/strong_migrations.rb:2
```

`strong_migrations` is in `group :development, :test` in the Gemfile, but its initializer references
the constant **unconditionally**. In production the gem is absent, so `config/environment.rb` raises
and **nothing boots** — not the server, not `assets:precompile`, not `db:migrate`. The app has almost
certainly never booted in production from this repo, which is consistent with `deploy.yml` having
stayed placeholders.

Fix: wrap the initializer body in `if defined?(StrongMigrations)`. **Verified** — with that guard,
`bin/rails runner` prints BOOT OK in production and `assets:precompile` completes, emitting the
23,767-byte Tailwind bundle. Do this first; every other item here is untestable until it lands.

### The rest, in build order

1. **A `Dockerfile`.** There isn't one — this app was upgraded from Rails 6 and never got the one
   `rails new` generates on Rails 8. Write it rather than relying on Nixpacks autodetection, because
   the build must run `assets:precompile` and Nixpacks has no reason to know that. **Verified good
   news:** the `tailwindcss:build` hook into `assets:precompile` works, so a correct Dockerfile gets
   the CSS for free. Use `SECRET_KEY_BASE_DUMMY=1` for the build step (the real key is a runtime
   secret). `bootsnap` is already in the Gemfile, so precompile it. Multi-stage, non-root runtime user.
   > **If this is skipped, the app deploys with no CSS at all.** `app/assets/builds/tailwind.css` is
   > gitignored and nothing rebuilds it at boot — that is the single most likely way the first deploy
   > looks broken while appearing to succeed.
2. **A health endpoint.** `config/routes.rb` has **no `/up`** — Rails 8 ships
   `get "up" => "rails/health#show"` but this app predates it. Coolify uses a health check to decide a
   container is live; without one it either never marks the deploy healthy or marks it healthy
   instantly and wrongly. Add the route. Note it must be reachable **before** the `config.hosts`
   allowlist and `force_ssl` interfere — test it, do not assume.
3. **Decide the Solid\* database layout.** `config/database.yml` production declares **four** DBs —
   `hoojah_production` plus `_cache`, `_queue`, `_cable` — each with `username: hoojah` and
   `HOOJAH_DATABASE_PASSWORD`. Coolify typically provisions **one** Postgres and hands you a
   `DATABASE_URL`. Two options: provision four databases on the one server, or collapse Solid
   Cache/Queue/Cable onto the primary. **Recommend collapsing at beta scale** — one connection string,
   one backup, and `solid_cable`'s `polling_interval: 0.1.seconds` is a small load. Whichever is
   chosen, the `migrations_paths` (`db/cache_migrate` etc.) must still be run.
4. **Env inventory.** Required: `RAILS_ENV=production`, `RAILS_MASTER_KEY`, `DATABASE_URL` (or the
   four), `APP_HOST` (feeds `config.hosts <<`, otherwise every request is blocked), and
   `RAILS_LOG_TO_STDOUT=1` so Coolify captures logs. Optional: `RAILS_LOG_LEVEL`,
   `RAILS_SERVE_STATIC_FILES` (needed **unless** the Dockerfile fronts with Thruster).
   **`config.force_ssl = true` + `config.assume_ssl = true` are already correct for Coolify** — its
   proxy terminates TLS, which is the same shape as the Kamal/Thruster assumption they were written
   for. Do not change them.
5. **Enable `config.require_master_key = true`** once `RAILS_MASTER_KEY` is set in Coolify. **This
   closes ledger item L4.** Note `config/master.key` does not exist locally either, so it must be
   generated or recovered — `credentials.yml.enc` is committed and useless without it.
6. **The Solid Queue worker is a second process.** `bin/jobs`. `config/recurring.yml` schedules
   `ConcludeStaleDebatesJob` daily at 3am, so without a worker, debates idle >7 days are never
   auto-concluded. Either a second Coolify service off the same image, or accept that the recurring
   job does not run and record it.
7. **`Procfile` says `-e ${RACK_ENV:-development}`.** If Coolify uses the Procfile and neither
   `RACK_ENV` nor `RAILS_ENV` is set, you get a **development-mode production app**. Fix the default
   or delete the Procfile in favour of the Dockerfile `CMD`.
8. **Delete `config/deploy.yml`** (and the `kamal` gem if nothing else wants it) — dead config now,
   and leaving it invites someone to "fix" the placeholders for a deploy path that is not used.
9. **One-time logout on first deploy** — the Rails 7.0 session key-generator change (SHA1→SHA256)
   invalidates existing sessions. Communicate it; it is expected, not a bug.

**Why here:** CI proves the suite is green, and a green suite that cannot deploy is worth much less.
Everything above is either a P0 boot bug or a first-deploy blocker, and none of it depends on the API
or stance work that follows.

**Main risk:** items 1–3 cannot be fully verified without an actual Coolify instance. Get a deploy
working end-to-end before declaring this done — a Dockerfile that builds locally is not evidence the
platform will run it.

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

## Slice 13 — Secret-ballot public counts (finding 2a) — **S** — ✅ DECIDED: **option C**

**Goal:** close the largest recorded secret-ballot gap — per-hoojah agree/neutral/disagree counts are
public and unsuppressed at any N, which `/dashboard`'s k=5 suppression does not touch.

**Owner decision, 2026-08-19: option C, the middle path.** (A was accept-and-document; B was blanket
k=5 suppression mirroring `/dashboard`.)

### What C means concretely

- **Below k=5 total votes:** show the **total vote count** and, for a signed-in viewer who has voted,
  **their own stance** — but **no per-stance breakdown and no percentages**. An anonymous viewer, or a
  signed-in one who has not voted, sees the total only.
- **At ≥ k=5:** unchanged from today — the full agree/neutral/disagree split with percentages.
- **k is `UserAnalytics::K` (5).** Share the existing constant; do **not** introduce a second one.
  A future change to the privacy floor must move both surfaces together or neither.

### Why C over A and B

It closes the actual inference vector rather than the whole display. The vector is low-N attribution:
at N=1 today, the hoojah owner sees a 100% single-stance breakdown, and pairing that with the
`new_vote` notification's timestamp (an accepted residual since Slice 5 — it reveals *that* a vote
landed and *when*, never *who*) narrows the voter to whoever was active. **C removes the breakdown at
low N, so the owner learns a vote happened but not which way it went** — which is the part that
matters. B closes the same vector but also blanks the total, so a fresh hoojah shows nothing useful at
exactly the moment a voter most wants to see their vote register.

### Scope — HTML *and* `Api::V1`, in the same slice

The suppression must apply to **both** surfaces or the API becomes the bypass: `HujahSerializer`
exposing raw `agree_count`/`neutral_count`/`disagree_count` would hand back precisely what the HTML
view just withheld. Files: the `_vote_bars` family, the hoojah card and show surfaces, and
`HujahSerializer`. Since there is no legacy API client (resolved above), the serializer's shape can
change outright.

**Main risk:** an inconsistent floor between the two surfaces. A request spec asserting that the API
and the HTML agree at N=4 and N=5 is the guard, and it is the spec to write first.

**Note:** `_distribution_bar` on `/dashboard` is **already** k=5-suppressed and is owner-only — do not
touch it. This slice is about the *public* surfaces it was contrasted with.

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

## ~~Parallel owner track — deploy readiness~~ — SUPERSEDED by Slice 10b

_Kept for the record. Written when Kamal was the assumed target; the owner confirmed **Coolify** on
2026-08-22, and probing it turned up a P0 production-boot bug this section did not know about._

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

- ~~**A confirmed live legacy API client**~~ — **resolved 2026-08-19: there is none.** The
  wire-format change stays breaking. This is no longer an open variable.
- **Real traffic arriving before CI lands** → swap 10 ↔ 11; the private-content API leak outranks
  enforcement.
- **The owner declaring native the business priority regardless** → Slices 11 and 12 compress into one
  pre-native hardening slice, with 13 riding behind. Worth arguing against: that compression is
  exactly how the Slice-2 Pundit migration left the API flags bug behind for eight slices.
