# Hoojah — Future Features Roadmap

_Date: 2026-08-05. Distilled from the 2013–2019 product case study
(https://rudzainy.github.io/work/2020-09-01-the-hoojah-project.html) + owner ask, mapped against the
shipped Rails 8.1 Hotwire app (Project 2 Slices 1–2, merged `afeb5ad`). Each feature area below feeds its
own future `brainstorming → spec → writing-plans → subagent-driven build` cycle; this is the roadmap, not
a spec._

## Vision (from the case study)

Hoojah is a **poll + debate platform focused on the arguments behind the votes**. The defining constraint
is the **3-option vote** (agree / neutral / disagree) with **arguments grouped by stance**, designed to
cut noise and decision fatigue. The signature interaction is a **one-on-one debate** — a "focused debate
lens" where two users exchange structured, turn-based arguments, escalated from the open threads. The
showcase also names an **analytics page**, **profiles with achievement badges**, **trending-arguments
sidebars**, and **identity verification**.

## Built vs unbuilt

| Vision element | Status |
|---|---|
| Timeline feed of claims/polls | ✅ Slice 1 |
| 3-option voting (agree/neutral/disagree) | ✅ Slice 1 |
| Arguments as stance-grouped threads | ✅ Slice 1 (filter) + Slice 2 (compose/respond) |
| Profile (view + edit) | ✅ Slice 2 |
| Notifications, flags/moderation, share | ✅ Slice 2 |
| Auth + authorization (Devise + Pundit) | ✅ Slices 1–2 |
| **One-on-one debate mode** | ❌ unbuilt — the signature differentiator |
| **User analytics dashboard** (privacy-gated) | ❌ unbuilt |
| **Internal social** (follow, trending, mentions, badges) | ❌ unbuilt |
| Identity verification | ❌ unbuilt (own future spec; out of this roadmap's depth) |

---

## ⚠️ Two cross-cutting items to decide BEFORE the dependent features

**1. Pre-existing privacy leak: `new_vote` notification exposes voter identity + timestamp.**
Votes are correctly a secret ballot at the serializer boundary (no `VoteSerializer`, `current_user_vote`
only returns the requester's own stance). **But** `Hujah#cast_vote` fires
`Notification.create!(category: :new_vote, subject_user_id: voter.id)` to the hoojah owner on a voter's
first vote, and `NotificationSerializer` renders `subject_user.username` — so **an owner already learns
who first-voted on their hoojah, and when** (just not their choice). This is the top de-anonymization
vector: any analytics time-series that splits by choice + fine time buckets lets an owner align a named
voter to a bucket and infer their vote. **Decision needed** (own small hardening slice, or fold into the
analytics spec): should `new_vote` notifications carry `subject_user_id` at all? A `rails-security-auditor`
pass is required. This gates the analytics **M** increment (trends), not the analytics MVP.

**2. Block / mute is a safety prerequisite for social at scale.** Not MVP, but the seam (a
`Block(blocker, blocked)` join filtered across feed / trending / mention lookup / notification creation,
and deleting the reciprocal follow) should be designed into the Follow model now so it slots in without a
rewrite.

---

## Feature area A — One-on-one Debate mode  *(signature feature)*

**Concept:** a `Debate` anchored to a hoojah between exactly two users taking opposing stances,
turn-based, escalated from an existing argument. Concluded debates are public read-only artifacts.

**Data model (new):** `debates` (`hujah_id`, `challenger_id`, `opponent_id`, `challenger_stance`,
`opponent_stance`, `status` enum pending/active/concluded/declined, `current_turn_user_id`, `max_rounds`,
`round`, friendly_id `slug`; partial-unique index on `(hujah_id, challenger, opponent)` where live to
block duplicate challenges) + `debate_turns` (`debate_id`, `user_id`, `body` raw→`format_body`,
`position`, `round`). **Kept separate from the `Hujah` tree** so turns don't pollute feed/vote/slug/flag
machinery. State machine on the model (`accept!`/`decline!`/`post_turn`/`conclude!`) mirroring `cast_vote`;
notifications via `after_*_commit`. New `Notification` enum values `debate_*` (append-only).

**Auth (Pundit):** `DebatePolicy` (show = concluded-public or participant; accept/decline = opponent when
pending; conclude = participant when active) + `DebateTurnPolicy` (create = the participant whose turn it
is). Per-action wiring per Slice 2 discipline.

**Hotwire:** request-driven Turbo Streams (append turn + replace composer) for MVP — human-paced, no
broadcasting needed. Reuse `dialog_controller` for the challenge modal. Pin `dom_id(debate, :transcript)`/
`(:composer)` now so Solid Cable broadcasting drops in later untouched.

**Increments:** ① **MVP** (challenge→accept/decline→turns→conclude, request-driven, notifications,
policies) — **M**, no blocking dep on unbuilt features. ② Spectator "who argued better?" verdict (reuse
the vote-counter idiom) **S** + real-time turns via Solid Cable (first broadcasting in the app) **S**.
③ Turn-timeout auto-conclude via Solid Queue **S**.

**Top open questions:** who-can-challenge-whom (harassment) — MVP anchors to an argument for context;
enforce opposing stances?; abandonment/timeouts; active-debate visibility (participants-only vs public
live); relationship to the existing argument thread (link, not replace).

---

## Feature area B — User Analytics dashboard  *(privacy-first)*

**Concept:** an **owner-only** `/dashboard` (no username in the URL, like `/notifications`) showing a user
their own content's performance. **Never** exposes who voted how.

**MVP (S, zero new tables):** per-hoojah vote-distribution summaries + totals (votes/arguments received) +
divisive-vs-consensus ranking — all from the **denormalized counts already on `hujahs`** (one grouped
query, no votes scan, no N+1). **Server-rendered SVG/Tailwind bars** (CSP-clean, no JS deps — the app
already renders vote bars server-side). `AnalyticsPolicy#show? = record.id == user.id`; Scope filters to
`current_user`.

**Hard privacy invariants:** no surface ever joins `votes → users`; no `VoteSerializer`, ever; **k-anonymity
(k ≥ 5)** — never render a breakdown below the threshold ("1 person disagreed"); **no per-vote timestamps**
— day/week buckets only; **never split fine time buckets by choice** (see cross-cutting item 1); the
vote-array change-history stays un-serialized; any metric describing *voters* (not the owner's content) is
out of scope without voter opt-in + security audit.

**Later:** ⓶ trends over time (rollup table via nightly Solid Queue job, k-suppressed) **M** — gated on the
`new_vote` notification decision. ⓷ reach/impressions (net-new, privacy-reviewed, aggregate-only
instrumentation) **L**; follower-growth **L** (depends on Follow).

**Requires a `rails-security-auditor` pass** on the policy/scope, k-suppression at the query layer, rollup
job (no identity in cache keys/args/logs), and confirmation no user-facing path joins votes→users.

---

## Feature area C — Internal social features

**Foundation → Follow.** `follows(follower_id, followed_id)` — unique `[follower, followed]`, index
`[followed]`, DB check `follower <> followed`; `after_create_commit` → `new_follower` notification +
maintain denormalized `followers_count`/`following_count` on `users`. Turbo follow/unfollow button
(`turbo_stream.replace` the button + count, no Stimulus). `FollowPolicy#create? = user.present?`,
`destroy? = owner`.

**Increments & sizing:**

| # | Increment | Size | Depends on |
|---|---|---|---|
| 1 | **Follow** (model, policy, Turbo button, counts, `new_follower` notif) | M | — foundation |
| 2 | **Following feed** (`from_followed_by` scope + Everyone/Following tabs on the existing pagy feed) | S | 1 |
| 3 | **@mentions** (`MENTION_RE` parse in a Solid Queue job, `mention` notif category, extend `format_body` safely, no-notify-on-edit, cap 10/hoojah) | M | Notification |
| 4 | **Badges** (`badges`/`user_badges`, seed, `AwardBadgesJob` off existing callbacks, profile chips, `badge_earned` notif; `debate_won` waits on area A) | M–L | callbacks; debates |
| 5 | **Trending** (recurring `ComputeTrendingJob` HN-style decay → Solid Cache, lazy Turbo-Frame sidebar, `lg` layout) | M | public data |
| 6 | Bookmarks/save *(optional)* | S | — |
| 7 | **Block/mute + private accounts** *(safety)* | L | 1 |

**Recommended MVP social slice: 1 + 2 + 3** — the coherent spine of the vision (follow people, see their
activity, get pulled back by mentions), reusing the feed / notification / `format_body` machinery.
Badges + Trending are a natural engagement fast-follow. **Reactions beyond the 3-option vote are NOT
recommended** — the vote already *is* the reaction primitive.

**Risks:** public vs private follows; mention spam / notification fatigue (categories grow 5→8);
trending gaming (brigading → weight distinct voters, decay, exclude self); badge farming (base on distinct
voters, immutable awards); counter drift (reconcile job); `updated_at`-ordering means voting resurfaces a
hoojah in the following feed (confirm desired).

---

## Recommended sequencing (owner decides)

All three MVPs are **independently buildable** on the shipped app. Suggested order:

1. **Debate MVP (A①)** — the signature differentiator, self-contained, highest vision value. *Or* start
   with **Social foundation (C1+2+3)** if engagement/substrate-for-later is the priority (Follow data pays
   forward to analytics reach + debate).
2. **Social foundation (C1–3)** if not first.
3. **Analytics MVP (B)** — after deciding the `new_vote` notification privacy item (cross-cutting #1);
   MVP itself is small and independent, but the trends increment is gated on that decision.
4. **Engagement fast-follow:** Badges + Trending (C4–5), debate verdict + real-time (A②).
5. **Safety slice:** Block/mute + private accounts (C7) before real scale.
6. Then **Project 3 (Hotwire Native)** — the debate/analytics/social URLs (friendly_id slugs, `/u/`,
   `/dashboard`, `/debates/:slug`) were all designed to be deep-link-friendly for it.

Each becomes its own brainstorm→spec→(3 specialist reviews)→plan→subagent-driven build, exactly like
Slices 1–2.
