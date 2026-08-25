# Design — Empty-state & error-journey coverage across all user journeys

Date: 2026-08-25
Status: approved (brainstorming) → ready for implementation plan
Scope decision: "Everything incl. errors" — empty collections + degenerate/why-empty
variants + error/edge journeys. Land as code (implement directly).
Approach: **A — Systematize** (extend the one primitive; add a real error controller).
CTA scope: **key funnels only** (empty global feed, empty tag page, empty own-profile).

## Problem

Hoojah has a mature empty-state primitive (`app/views/ui/_empty_state.html.erb`) used on ~9
surfaces, but a full journey audit found collections that render **blank** when empty, degenerate
"why is this empty" cases that give wrong guidance, off-design-system one-offs, and unbranded
default Rails error pages. This design closes every gap under a single consistent approach.

## Gap inventory (from the journey audit)

### Empty-collection gaps
1. **Global feed** (`hujahs/index.html.erb:29`) — only `filter=following` has an empty branch. The
   default tab renders `#hujah-feed` over an empty collection → a **blank front page** for an
   anonymous visitor or a fresh install. **HIGH**
2. **Tag page** (`tags/show.html.erb:18`) — no empty branch at all; worsened by the header reading
   `@tag.hujahs_count` while the list applies private/blocked/visibility filters, so the header can
   claim "5 hoojah tagged" over an empty list. **HIGH**
3. **Response stance-filter tabs** (`_response_filter.html.erb` + `response_filter_controller.js`) —
   filtering is pure client-side show/hide; selecting a stance with zero matching responses hides
   every card and leaves a **blank void** with no placeholder. **HIGH**
4. **Notifications filter pills** (`notifications/index.html.erb:38`, `read_all.turbo_stream.erb`) —
   "You have no notifications" shows for a filtered-empty subset (e.g. Mentions) even when other
   notifications exist. **MEDIUM**
5. **Search** (`search/_results.html.erb:23`, `search/_hashtag_chips.html.erb`) — zero-results is a
   hand-rolled `<p class="text-ink-2">` with no glyph (off the design system); the empty hashtag
   cloud renders bare headers over empty space. **MEDIUM**
6. **Profile Debates tab** (`users/show.html.erb:57`) — "No debates yet" uses the default
   `message-circle` glyph, contradicting the `swords` glyph used for the same sentence on
   `hujahs/show.html.erb:141`. **MEDIUM**
7. **Following feed** (`hujahs/index.html.erb:24`) — "Follow some people…" is wrong guidance when
   you already follow people who are simply silent or filtered. **MEDIUM**
8. **LOW polish**: "No response yet" singular grammar (`_response_filter.html.erb:77`);
   declined-debate body has no closing line; profile empty copy identical for owner vs visitor;
   verdict "0 spectators" wording (already a documented deferred item — leave).

### Error-journey gaps
9. **404 / 422 / 500** are the **default unbranded Rails pages** (`public/404.html` etc. still carry
   `rails-default-error-page`). **HIGH**
10. **`head :not_found`** in `hujahs_controller.rb` and `tags_controller.rb` returns a **genuinely
    blank body** (a 404-status empty response is not routed through the static error page). **HIGH**
11. Pundit `NotAuthorizedError` → redirect-back-with-alert. **Already handled — leave as is.**

## Design

### 1. Extend `ui/_empty_state` (additive, backward-compatible)
Add optional locals to the existing primitive; **all 9 current call sites remain byte-identical**
because the new locals default to nil:
- `cta_label:` and `cta_href:` — when both present, render **one** pill button below the sentence
  using `ds_button_classes` (house pill style). When absent, output is exactly as today.
- When a CTA is present, the block lays out centered/stacked; otherwise the current inline
  glyph+sentence row is unchanged.
- Guard against Tailwind rule drift with the md5-bundle check from CLAUDE.md (baseline hash before,
  positive control after) — any new interpolated button tone must be `@source inline(...)`
  safelisted if not already covered by `ds_button_classes`.

### 2. Empty-collection fixes (all via the primitive)
- **Global feed** — add an empty branch on the default tab:
  - signed-in: "No hoojahs yet" + CTA **"Post the first hoojah"** → `new_hujah_path`.
  - anonymous: "No hoojahs yet — sign up to start the conversation" + CTA → `new_user_registration_path`.
- **Tag page** — empty branch "No hoojahs tagged #<tag> yet" (+ compose CTA when signed in), and
  change the header count to the **visible** count (the filtered `@hujahs`/a count query), not
  `@tag.hujahs_count`, so header and list can never disagree.
- **Stance-filter void** — `better-stimulus` fix: an always-rendered, initially-hidden placeholder
  in `_response_filter.html.erb`; `response_filter_controller.js` toggles it when the visible count
  for the selected stance is 0, with per-stance copy ("No agreeing/neutral/disagreeing responses
  yet"). One-liner, no CTA.
- **Notifications** — reason-aware message keyed on `@filter`: `mentions` → "No mentions yet";
  `debates` → "No debate activity yet"; else → "You have no notifications". Applied in both
  `index.html.erb` and `read_all.turbo_stream.erb`.
- **Search** — route zero-results through `ui/_empty_state` (glyph `search-x` or `search`, faint-grey
  token); give the empty hashtag cloud its own one-liner ("No hashtags yet").
- **Following feed** — reword to cover both states: "When people you follow post, you'll see it
  here." (no misdirection); keep it off-CTA per scope (not a key funnel).
- **Profile Debates tab** — use `swords` glyph to match the hujah page; owner-only first-run CTA on
  the Hoojahs tab ("Post your first hoojah") — key-funnel CTA; visitor keeps the plain one-liner.
- **LOW polish** — "No responses yet" plural; a one-line closing sentence in the declined-debate body.

### 3. Branded error pages
- `ErrorsController#show` — `skip_authorization`, renders `app/views/errors/show.html.erb` inside the
  app layout, status derived from the request path. One-line copy per code + a "Back to feed" CTA:
  - 404 "That page doesn't exist." · 422 "That request couldn't be processed." · 500 "Something went
    wrong on our end."
- Wire `config.exceptions_app = routes` (production) and route `/404`, `/422`, `/500` →
  `errors#show`. Keep `config.consider_all_requests_local = false` in production.
- Convert the `head :not_found` sites in `hujahs_controller.rb` and `tags_controller.rb` to raise
  `ActiveRecord::RecordNotFound` after `skip_authorization`, so a missing slug flows through the
  branded 404 instead of a blank body. Confirm `verify_authorized` is still satisfied (the rescue
  path calls `skip_authorization` before raising).
- Rebrand `public/500.html` (last-resort, DB/boot-down) to match the visual language; `public/404.html`
  and `422.html` become unreachable in production once `exceptions_app` routes dynamically, but
  rebrand them too so dev/edge cases stay consistent.

### 4. Component boundaries
- `ui/_empty_state` — one purpose: render a faint one-liner, optionally with a single CTA. No screen
  logic leaks in; callers pass final copy + href.
- `ErrorsController` — one purpose: map an error status to a branded page. No business logic.
- `response_filter_controller.js` — owns the client-side filtered-empty placeholder toggle; no server
  round-trip.

## Testing
- Request specs asserting the empty message renders for: global feed (signed-in + anonymous variants),
  tag page (empty + count-consistency), notifications filtered-empty per filter, search zero-results,
  and the error routes (`/404`, `/422`, `/500` render branded body + correct status).
- A system spec (`js: true`) for the stance-filter placeholder: post agreeing responses only, tap
  Disagree, assert the placeholder appears and cards hide.
- `bin/ci` green (gates + specs). Tailwind md5 bundle check for the primitive change. StandardRB,
  Brakeman, bundler-audit stay green.

## Build workflow (as requested)
- **Fable orchestration** — Fable 5 as architect/advisor: plans slice ordering, writes per-task
  briefs, reviews diffs; **Opus 4.8 executes** the token-heavy edits (advisor + architect-and-delegate
  wiring per the `fable-orchestration` skill).
- **Subagent-driven development** — each fix group is an isolated task → implementer subagent →
  `superpowers:code-reviewer` independent review → batched fixes → re-verify.
- Specialized agents: `better-stimulus` for the stance-filter controller.

## Out of scope
- Verdict small-N suppression (documented deferred item).
- Blocked-profile dedicated surface beyond existing Unblock control (functional, not empty-state).
- Any redesign of the empty-state visual language (no illustrations/emoji/animation — design-system rule).
