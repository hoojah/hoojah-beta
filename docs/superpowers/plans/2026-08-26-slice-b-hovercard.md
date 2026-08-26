# Plan: Slice B — User hovercard + click-to-profile everywhere

**Spec (authoritative):** `docs/superpowers/specs/2026-08-26-navbar-hovercard-follows-design.md` → "Slice B".
**Depends on:** Slice C (landed) — `User#followers_count` / `User#following_count` counter-cache
columns exist and are the correct count source. The hovercard MUST read those, never
`.followers.size`.

## Goal

Hovering any user's avatar / full name / `@username` on **any** surface shows a small profile
card after a short delay; clicking navigates to `/u/:username`. Card content is **Standard**
fields for a visible user and a **gated minimal set** for a private stranger. Guests may view
public cards. Touch devices and JS-off degrade to a plain link (no card).

## Cross-cutting conventions (apply to every task)

- **CSRF / routing:** the card endpoint is read-only → it is a **main route, not `Api::V1`**, so
  CSRF stays enforced (CLAUDE.md "two surfaces, two CSRF strategies"). `ApplicationController`
  runs `after_action :verify_authorized`, so `#card` MUST call `skip_authorization` exactly once
  (mirrors `users#show` / `users#followers`).
- **Tailwind v4 discipline (CLAUDE.md "Tailwind gotchas"):**
  - Prefer **literal** class strings in ERB. Any class assembled in JS or by string
    interpolation needs an `@source inline(...)` entry — enumerated per task below.
  - `.js` and `.erb` files (including `<%# … %>` comments) **are scanned**. Do not name a
    concrete deleted class in a comment (it resurrects the rule). `docs/`, `spec/`, `.github/`,
    `bin/`, `app/assets/images` are `@source not`-excluded; `app/javascript/**` is **not**, so a
    literal class in a controller string does compile — but treat that as fragile and safelist
    JS-built panel classes explicitly.
  - After any comment-only edit: `md5` the built `tailwind.css` before/after — it must not
    change. Pair with a positive control (append a comment naming an unused class, confirm the
    hash moves) so a broken harness is not mistaken for a clean result.
  - `@source inline` paths and the safelist cover the **bare** utility only.
- **Quality gates:** StandardRB, Brakeman, bundler-audit, prosopite (log-only) per CLAUDE.md.
- **No Claude/Anthropic branding in commits.** Commit subjects: plain imperative.
- **Shared Postgres test DB** — run one suite at a time; use targeted specs while iterating.
- Do **not** run `git commit` as part of a task unless the executing session's workflow says so;
  each task ends with its own specs + gates, and the whole slice ends with `bin/ci`.

## Nested-anchor constraint (read before Tasks 3–5)

An `<a>` inside an `<a>` is invalid HTML — the browser splits the outer anchor and the row's
click breaks. Render points fall into two shapes:

- **Standalone bylines** (not wrapped in an outer content link): feed `_hujah_header`, hujah
  `show`, `_child_card`, all debate views, `_notification_card` actor, `_flagged_hujah`, and the
  already-`profile_path`-linked `_user_row` / `_result_user`. These take `ui/_user_link` cleanly.
- **Bylines nested inside a card-level link to the hoojah** — `search/_result_hujah` (whole row
  is `link_to hujah_path`), `users/_user_hujah` (same), `trending/_trending` (same). Here a
  profile anchor would nest inside the hoojah anchor. These require the **stretched-link
  restructure** in Task 5 — do not naively wrap.

## Render-points checklist (every surface; nothing may be missed)

| # | File | Lines | Current | Shape | Task |
|---|------|-------|---------|-------|------|
| 1 | `app/views/hujahs/_hujah_header.html.erb` | 59–61 avatar, 63 name, 65 `@handle` | avatar+name link to **dead `"#"`**; handle plain | standalone | 3 |
| 2 | `app/views/hujahs/show.html.erb` | 78 avatar, 80 name, 82 `@handle` | plain text | standalone | 3 |
| 3 | `app/views/hujahs/_child_card.html.erb` | 43 avatar, 45 name, 46 `@handle` | plain text | standalone | 3 |
| 4 | `app/views/debates/_debate_pending.html.erb` | 25/29 avatars, 33/37 `@handle` (stance-coloured) | plain text | standalone | 4 |
| 5 | `app/views/debates/_debate_scoreboard.html.erb` | 37/51 `@handle` (+ nearby avatars) | plain text | standalone | 4 |
| 6 | `app/views/debates/_debate_turn.html.erb` | avatar (`sm`), 56 `@handle` | plain text | standalone | 4 |
| 7 | `app/views/debates/_verdict.html.erb` | 45/46, 86, 139 `@handle` | plain text | standalone | 4 |
| 8 | `app/views/debates/new.html.erb` | 57 name, 58 `@handle` (+ avatar) | plain text | standalone | 4 |
| 9 | `app/views/notifications/_notification_card.html.erb` | ~86 actor tile, 99–119 `<strong>@handle</strong>`, 160/172 "View profile" | strong is plain; View-profile already `profile_path` | standalone | 4 |
| 10 | `app/views/moderation/_flagged_hujah.html.erb` | 11 name, 12 `@handle` (+ avatar) | plain text | standalone | 4 |
| 11 | `app/views/users/_user_row.html.erb` | 41, 53 `link_to profile_path` | already linked | standalone (swap) | 5 |
| 12 | `app/views/search/_result_user.html.erb` | 16 `link_to profile_path` wrapping avatar+name | already linked | standalone (swap) | 5 |
| 13 | `app/views/search/_result_hujah.html.erb` | 10 outer `link_to hujah_path`; 13 avatar, 16 `@handle` | nested-in-card-link | 5 (restructure) |
| 14 | `app/views/users/_user_hujah.html.erb` | 26 outer `link_to hujah_path`; 33 name, 34 `@handle` | nested-in-card-link | 5 (restructure) |
| 15 | `app/views/trending/_trending.html.erb` | 27 outer `link_to hujah_path`; 29 `@handle` | nested-in-card-link | 5 (restructure) |

**Explicitly out of scope:** the navbar own-avatar `<details>` dropdown (it is a `<summary>`
trigger, not a profile link — leave it). `_verdict` share-text Ruby strings (155–156) and
`debates/new`'s `submit_tag` label (148) are plain strings, not render points — do not touch.
`_notification_card` handles where `subject_user` is nil (`new_vote`, `moderation_removed`) must
**not** be wrapped (guard on `subject_user.present?`).

---

## Task 1 — Card endpoint + route + `users/card` template + hovercard partials (+ request specs)

**Rationale:** Build the data layer first. It is fully testable via request specs with no JS, and
Task 2's `ui/_user_link` depends on the `user_card_path` route existing. Nothing renders it into a
page yet, so this task is safe and isolated.

**Files to create/edit:**
- **Edit `config/routes.rb`** — add beside the profile routes (after `get "/u/:username" …`):
  ```ruby
  # Hovercard body (Slice B). Read-only → main route (NOT Api::V1) so CSRF strategy is
  # unchanged; #card calls skip_authorization like users#show. layout:false partial fetched
  # by hovercard_controller.js on hover. :username, not id (no friendly_id on User).
  get "/u/:username/card", to: "users#card", as: :user_card
  ```
  Place it so the more specific `/card` does not shadow `/edit` etc. (order among the sibling
  `/u/:username/*` routes is fine; Rails matches full segments).
- **Edit `app/controllers/users_controller.rb`** — add a `card` action. `set_user` (the existing
  `before_action`, `User.find_by!(username:)`) already gives a **404 on unknown username** and
  runs for `card`. `authenticate_user!` is only on `edit`/`update`, so `card` is reachable by
  guests — correct.
  ```ruby
  def card
    skip_authorization
    @gated = !@user.visible_to?(current_user)
    render "users/card", layout: false
  end
  ```
  Reuse the exact `@gated = !@user.visible_to?(current_user)` gate `show` uses — do not invent a
  second privacy predicate.
- **Create `app/views/users/card.html.erb`** — the bare (layout-less) template that dispatches:
  ```erb
  <%# Slice B hovercard body. layout:false; fetched by hovercard_controller.js on hover and
      injected into the shared floating panel. Standard fields for a visible user; the gated
      minimal whitelist for a private stranger (same gate as users#show). %>
  <% if @gated %>
    <%= render "users/hovercard_gated", user: @user %>
  <% else %>
    <%= render "users/hovercard", user: @user %>
  <% end %>
  ```
- **Create `app/views/users/_hovercard.html.erb`** (Standard). Content, styled to sit **inside**
  the JS-owned panel (so this partial provides padding/content, the panel provides
  bg/shadow/rounded chrome — mirror the `ui/_menu` surface look):
  - `render "ui/avatar", user: user, size: :md`
  - `user.full_name` (bold, `text-ink`), `@<%= user.username %>` (`text-xs text-ink-2`).
  - `user.headline` when present (`text-sm text-ink-2`, truncated / clamped).
  - Follower + following counts **from `user.followers_count` / `user.following_count`** — reuse
    `render "users/follower_count", user: user` for the follower chip (it already reads the
    counter-cache column and self-wraps in its `dom_id`) and mirror it for following (`user-plus`
    icon + `user.following_count`). Do **not** call `.followers.size`.
  - `render "users/follow_button", user: user` — that partial already hides itself for self and
    for guests, and its `button_to`s are on CSRF-protected main routes.
  - Wrap in a single root `<div class="p-3 w-72">` (or similar) — content padding/width only; the
    panel chrome comes from Task 2's JS wrapper. Keep classes **literal**.
- **Create `app/views/users/_hovercard_gated.html.erb`** (minimal whitelist, mirrors
  `users/_gated_header`): avatar (`md`), full name, `@handle`, a "Private account" line
  (`lucide_icon("lock", …)` + text), `render "users/follow_button", user: user`, and
  follower/following counts (counter-cache columns). **No** headline / location / link / badges.
  This is the leak boundary — every omitted field is omitted on purpose.

**Tailwind:** all classes here are literal ERB → **no new `@source inline` entries** from this
task. (`bg-card shadow rounded` already emit via `ui/_menu`; they belong to Task 2's panel
anyway.)

**Specs to write — `spec/requests/user_card_spec.rb`:**
- Public user, signed-in viewer → 200; body contains full name, `@username`, and the
  follower/following counts; renders the Standard partial (assert on a Standard-only marker,
  e.g. headline text when set).
- Public user, **guest** (not signed in) → 200 (guests may view public cards).
- **Private** user viewed by a **stranger** → 200 but renders the **gated** partial: contains
  "Private account", the follow button, and counts; must **not** contain headline/location/link
  (assert their absence).
- Private user viewed by an **accepted follower** and by **self** → Standard partial.
- Unknown username → **404**.
- Response carries no application layout (`layout: false`) — assert the navbar is absent.

**Acceptance:** endpoint returns correct partial per visibility; 404 on unknown; guest allowed on
public; no layout; counts read from the counter-cache columns. Request specs green; StandardRB /
Brakeman clean.

---

## Task 2 — `hovercard_controller.js` + `ui/_user_link` partial + Tailwind safelist

**Rationale:** The client layer. Depends on Task 1's `user_card_path`. Adds the reusable anchor
partial and the Stimulus controller, plus the one place new interpolated/JS-built classes enter
the safelist. No render points are wired yet (so nothing changes visually), except an optional
single smoke wiring for the system harness — keep production surfaces untouched until Tasks 3–5.

**Files to create:**
- **Create `app/views/ui/_user_link.html.erb`** — a **layout partial** (like `ui/_card` /
  `ui/_menu`; `class` cannot be a strict-locals param). Called as:
  ```erb
  <%= render layout: "ui/user_link", locals: {user: some_user, class: "…"} do %>…block…<% end %>
  ```
  Emits a genuine anchor so click / keyboard / no-JS all work:
  ```erb
  <%# Slice B. A real <a> to the profile that also triggers the hovercard. Genuine anchor so
      keyboard focus, middle-click, and JS-off all navigate. Wrap avatar and/or name at each
      user render point with it. Do NOT nest inside another <a> (invalid HTML) — see the plan's
      nested-anchor note; card-wrapped bylines use the stretched-link restructure instead.
      class:/data attrs literal → no Tailwind interpolation here. %>
  <%= link_to profile_path(local_assigns.fetch(:user).username),
        class: "no-underline #{local_assigns[:class]}".squish,
        data: {
          controller: "hovercard",
          hovercard_username_value: local_assigns.fetch(:user).username,
          hovercard_url_value: user_card_path(local_assigns.fetch(:user).username),
          action: "mouseenter->hovercard#scheduleShow mouseleave->hovercard#scheduleHide " \
                  "focusin->hovercard#scheduleShow focusout->hovercard#scheduleHide"
        } do %><%= yield %><% end %>
  ```
- **Create `app/javascript/controllers/hovercard_controller.js`** (auto-registered by the
  existing `eagerLoadControllersFrom("controllers", …)` in `controllers/index.js` — no manual
  registration). Behaviour:
  - `static values = { username: String, url: String }`.
  - **Module-scoped singletons** (shared across all instances, declared outside the class):
    a `cache = new Map()` (username → fetched HTML string) so repeat hovers don't refetch, and a
    lazily-created single `panel` element appended to `<body>`.
  - **Touch/coarse-pointer guard:** in `scheduleShow`, if
    `window.matchMedia("(pointer: coarse)").matches`, return immediately — the anchor click just
    navigates, no card.
  - `scheduleShow()`: set a ~400 ms timer; on fire, `fetch(this.urlValue, {headers: {Accept:
    "text/html"}})` **once** (populate/read `cache` by `usernameValue`), inject HTML into the
    shared panel, position it viewport-aware (see below), and fade in
    (`opacity-0`→`opacity-100`, remove `pointer-events-none`). Record which username the panel
    currently shows so a stale in-flight fetch for a different trigger is ignored.
  - **Panel chrome** (set once when the panel is created): `bg-card shadow rounded fixed z-50 w-72
    opacity-0 pointer-events-none transition-opacity duration-150`. Shown state toggles
    `opacity-0`↔`opacity-100` and `pointer-events-none`.
  - **Positioning:** compute from the trigger's `getBoundingClientRect()`; the panel is `fixed`,
    so set `panel.style.top` / `panel.style.left` as **inline styles** (not Tailwind). Default
    below the trigger; **flip above** if it would overflow the viewport bottom; **clamp
    horizontally** into the viewport (min 8 px gutter). Inline styles keep positioning out of the
    Tailwind surface.
  - **Keep-open bridge:** the panel itself listens `mouseenter` (cancel any pending hide) /
    `mouseleave` (start hide) so moving the cursor trigger→card keeps it open.
  - `scheduleHide()`: ~200 ms grace timer; on fire, hide unless the pointer is over the trigger or
    the panel.
  - **Dismiss** on `scroll`, `keydown` Escape, click-away (a document click outside trigger+panel),
    and `teardown()` (the one-time `turbo:before-cache` loop in `application.js:14` already calls
    `c.teardown?.()` on every controller — implement `teardown()` to hide the panel and clear
    timers, exactly like `dialog_controller.js`).
  - `disconnect()`: clear this instance's timers and remove any document-level listeners it added
    (mirror `search_controller.js`'s `disconnect` and `dialog_controller`'s teardown discipline).
  - Fetched HTML contains a `button_to` form (the follow button). The card is injected as-is; the
    form's authenticity token is server-rendered into the partial, so no CSRF handling is needed
    client-side.
- **Edit `app/assets/tailwind/application.css`** — add the panel safelist entry beside the
  existing `@source inline(...)` block. These are built in JS (fragile to rely on JS scanning) and
  must be forced in:
  ```css
  /* Slice B hovercard panel chrome — assembled in hovercard_controller.js, so safelisted
     rather than trusted to the JS source scan. Positioning is inline style, not utilities. */
  @source inline("fixed z-50 w-72 opacity-0 opacity-100 pointer-events-none transition-opacity duration-150");
  ```
  (`bg-card`, `shadow`, `rounded` already emit via `ui/_menu` — no need to re-list, but harmless.)
  **Do the md5-before/after + positive-control bundle check** described in the conventions.

**Specs to write/run:**
- No production render point uses `ui/_user_link` yet, so add a **view spec** (or a tiny throwaway
  fixture render) asserting `ui/_user_link` emits an `<a href="/u/<username>">` carrying
  `data-controller="hovercard"`, `data-hovercard-username-value`, `data-hovercard-url-value`
  (= `/u/<username>/card`), and the four `data-action` bindings — and that the block content is
  yielded inside the anchor.
- A **compiled-CSS spec** (using `TailwindBuild.once!` / `TailwindBuild.emitted?`,
  `spec/support/tailwind_build.rb`) asserting the panel utilities (`z-50`, `w-72`,
  `transition-opacity`, `opacity-100`) are emitted.
- JS has no unit harness here — its behaviour is covered by Task 6 system specs.

**Acceptance:** `ui/_user_link` renders the correct anchor + data attributes; controller
auto-registers; panel classes emit; bundle md5 unchanged on comment-only edits; StandardRB clean
(note `bin/**` and `db/**` are StandardRB-excluded, not `app/javascript` — but there is no Ruby
here to format).

---

## Task 3 — Convert Batch A: feed byline + hujah show + reply cards

**Rationale:** Highest-value, lowest-risk standalone bylines first — the feed byline currently
links to **dead `"#"` placeholders**, so this batch both adds hovercards and fixes a real bug. All
three are standalone (no outer content anchor), so `ui/_user_link` applies directly.

**Files to edit:**
- **`app/views/hujahs/_hujah_header.html.erb`** — replace `link_to "#"` around the avatar
  (lines 59–61) with `render layout: "ui/user_link", locals: {user: hujah.user, class: "shrink-0"}`
  wrapping the `ui/avatar` render; replace `link_to hujah.user.full_name, "#"` (line 63) with a
  `ui/_user_link` wrapping the name span (keep `text-ink font-bold truncate`). Leave the
  `@username`+`time` `<small>` (lines 64–70) as-is — wrapping it would put the timestamp inside a
  profile anchor. Do **not** touch the parent-stub link (line 44 → `hujah_path(parent.slug)`;
  that is a hoojah link, correct as-is).
- **`app/views/hujahs/show.html.erb`** — wrap the avatar (line 78) and the `full_name` div
  (line 80) each in `ui/_user_link` (`user: @hujah.user`). Leave the `@username`+time block.
- **`app/views/hujahs/_child_card.html.erb`** — wrap the avatar (line 43) and the `full_name` div
  (line 45) in `ui/_user_link` (`user: child.user`). Leave the `@username`+stance line.

**Notes:** pass box size through `ui/_avatar`'s `size:`/`variant:` as today (never a `w-*` in
`class:` — see the avatar partial header). `ui/_user_link` adds `no-underline`; keep existing text
utilities via its `class:` local.

**Specs to write/run:**
- **`spec/views/` or request spec** asserting the feed byline avatar and name now link to
  `profile_path(hujah.user.username)` and **no longer contain `href="#"`** (the spec explicitly
  called for in the design). Assert the same for `show` and `_child_card`.
- Re-run existing `spec/requests/hujahs_spec.rb` / feed specs and any `_child_card` coverage to
  confirm no regression.

**Acceptance:** no `"#"` links remain in these three partials; avatar+name link to the author's
profile and carry the hovercard data attributes; existing card menu / layout unchanged.

---

## Task 4 — Convert Batch B: debates + notifications + moderation

**Rationale:** The remaining standalone bylines, grouped because they share the "wrap avatar +
`@handle` with `ui/_user_link`" mechanic and touch a disjoint file set from Batch A.

**Files to edit:**
- **`app/views/debates/_debate_pending.html.erb`** — wrap the two avatars (25/29) and the two
  `@handle` spans (33 challenger `text-agree`, 37 opponent `text-disagree`). Preserve the stance
  colour by passing it through `ui/_user_link`'s `class:` (e.g. `class: "text-agree"`).
- **`app/views/debates/_debate_scoreboard.html.erb`** — wrap the `@handle`s (37/51) and their
  adjacent avatars with `ui/_user_link` for `debate.challenger` / `debate.opponent`.
- **`app/views/debates/_debate_turn.html.erb`** — wrap the `sm` avatar and the `@handle` (56) for
  `debate_turn.user`.
- **`app/views/debates/_verdict.html.erb`** — wrap the participant `@handle`s (45/46 tuple, 86,
  and the closing-turn handle 139) with `ui/_user_link`. **Do not** touch the share-text strings
  (155–156) — they are plain Ruby strings for the share sheet, not rendered handles.
- **`app/views/debates/new.html.erb`** — wrap the argument author avatar, `full_name` (57) and
  `@handle` (58) with `ui/_user_link` (`user: @argument.user`). Leave the `submit_tag` label (148).
- **`app/views/notifications/_notification_card.html.erb`** — wrap the actor tile avatar (~86,
  `actor_tile` branch) and each `<strong>@handle</strong>` (99–119) in `ui/_user_link`, **guarded
  on `notification.subject_user.present?`** (several categories — `new_vote`, `moderation_removed`
  — have a nil `subject_user` by construction; those branches must stay unwrapped and unchanged).
  The existing "View profile" links (160/172) already point to `profile_path` — optionally add the
  hovercard data attributes by routing them through `ui/_user_link`, but do not change their
  visible label/behaviour.
- **`app/views/moderation/_flagged_hujah.html.erb`** — wrap the avatar, `full_name` (11) and
  `@handle` (12) with `ui/_user_link` (`user: hujah.user`).

**Specs to write/run:** re-run `spec/requests/debates_spec.rb`, `spec/requests/notifications_spec.rb`
(or equivalents) and moderation request specs; add assertions that a debate participant handle and
a notification actor handle now render as `a[href="/u/<username>"]` with `data-controller="hovercard"`.
Confirm nil-`subject_user` notification categories still render without raising and without a link.

**Acceptance:** every listed handle/avatar links to the profile with hovercard data attributes;
stance colours preserved; nil-actor notifications unchanged; specs green.

---

## Task 5 — Convert Batch C: already-linked swaps + nested-in-card-link restructures

**Rationale:** The trickiest batch, isolated on purpose. Two sub-groups: (a) surfaces already
linked to `profile_path` — a mechanical swap to gain hovercard behaviour; (b) three surfaces where
the whole card is a link to the **hoojah**, which need the stretched-link restructure to avoid
nested anchors. Keeping this separate lets its review focus on HTML validity and click behaviour.

**Sub-group A — swap existing profile links to `ui/_user_link` (add hovercard triggers):**
- **`app/views/users/_user_row.html.erb`** — the two `link_to profile_path` (41, 53) become
  `ui/_user_link` (preserve their `class:` — `flex items-center gap-3 flex-1` etc.). The
  Remove-follower `button_to` (surface-gated, sibling of the link) is untouched.
- **`app/views/search/_result_user.html.erb`** — the `link_to profile_path` (16) wrapping
  avatar+name becomes `ui/_user_link` (keep `flex items-center gap-3 flex-1 min-w-0`). The follow
  button sits **outside** this link (a sibling) and stays put — do not pull it inside.

**Sub-group B — stretched-link restructure (nested-anchor surfaces):**
For each, the outer element stops being an `<a>` and becomes a positioned container; the hoojah
link becomes an inset overlay anchor; the user byline becomes a `ui/_user_link` stacked above it.
Pattern:
```erb
<div class="relative …">                          <%# was the outer <a> %>
  <%= link_to hujah_path(hujah.slug),
        class: "absolute inset-0 z-0", aria-label: "Open hoojah" do %><% end %>
  … card content …
  <%= render layout: "ui/user_link",
        locals: {user: hujah.user, class: "relative z-10 …"} do %>@<%= hujah.user.username %><% end %>
</div>
```
The overlay anchor carries the card's click-through to the hoojah; the `ui/_user_link` sits
`relative z-10` so it captures its own clicks/hover. Verify the card's existing hover/`shadow`
styling still reads (move any `hover:` utility that lived on the old `<a>` onto the container or
the overlay as appropriate).
- **`app/views/search/_result_hujah.html.erb`** — outer `link_to hujah_path` (10) → container +
  inset overlay; wrap avatar (13) and the `@username` in "Hoojah by @…" (16) with `ui/_user_link`.
- **`app/views/users/_user_hujah.html.erb`** — outer `link_to hujah_path` (26) → container + inset
  overlay; wrap the author `full_name` (33) and `@username` (34).
- **`app/views/trending/_trending.html.erb`** — outer `link_to hujah_path` (27) → container +
  inset overlay; wrap the compact `@username` (29).

**Fallback (record the decision in the commit/PR):** if the stretched-link restructure proves too
invasive for a given compact surface (e.g. trending's tight row), that surface may keep the
hoojah-only link and **defer** its byline hovercard, documented explicitly — do **not** ship
nested anchors. Prefer the restructure; defer only with a written rationale.

**Specs to write/run:** assert `_user_row` / `_result_user` links still resolve to `profile_path`
and now carry `data-controller="hovercard"`; assert the three restructured surfaces render the
hoojah link **and** a separate `profile_path` link (both present, not nested — a validity check via
Nokogiri that no `<a>` is a descendant of another `<a>`). Re-run search + trending + profile
request/system specs.

**Acceptance:** every Batch-C surface exposes a working profile hovercard trigger; the card's
primary click still reaches the hoojah on the restructured surfaces; no nested anchors; specs green.

---

## Task 6 — System specs + final `bin/ci`

**Rationale:** End-to-end verification of the JS behaviour (which unit specs can't cover) and the
whole-slice gate.

**Files to create:**
- **`spec/system/hovercard_spec.rb`** (tagged `js: true`, headless Chrome via Cuprite):
  - Hovering a feed byline avatar/name shows the card after the delay; the card contains the
    author's full name and follower/following counts.
  - Moving the cursor from the trigger onto the card keeps it open; leaving both hides it.
  - Escape / scroll / click-away dismiss the card.
  - **Clicking** the byline navigates to `/u/:username` (assert `current_path`) — proves the dead
    `"#"` links are gone end-to-end.
  - **Private stranger**: card shows the gated minimal set ("Private account", follow button,
    counts) and omits headline/location.
  - **Guest** on a public author: hovering shows the Standard card.
  - Touch/no-JS degradation: at minimum assert the anchor has a real `href` so a JS-off / coarse-
    pointer client still navigates (simulating `pointer: coarse` in Cuprite is unreliable — assert
    the href/degradation contract rather than the media-query branch if the driver can't emulate it;
    note this limitation in the spec).
  - Guard against `have_broadcasted_to … .with { }` misuse (not relevant here, but keep the
    single-panel assumption explicit in assertions).
- Extend/confirm the Task 3 view assertion (feed byline → `profile_path`, not `"#"`) is part of the
  committed suite.

**Final gate:**
- Run `bin/ci` (the definition of record; `.github/workflows/ci.yml` calls it). It builds Tailwind
  before RSpec — required because the bundle is gitignored and the panel safelist must compile.
  Watch for the shared-test-DB `PG::ObjectInUse` hazard (run alone); heed the memory note about
  `rm -rf public/assets` before mid-phase JS system specs if asset staleness bites.
- Confirm `grep -c 'N+1 queries detected' log/prosopite.log` has not regressed materially (the card
  endpoint loads a single user; use `with_attached_avatar` if a prosopite report flags the avatar).

**Acceptance:** all system specs green; `bin/ci` green (gates + 530+ specs + Tailwind build); no new
Tailwind orphan rules (bundle md5 stable on comment-only edits); no nested anchors anywhere.

---

## Ordering rationale (summary)

Strict dependency chain: **1 → 2 → {3, 4, 5} → 6**. Task 1 builds the testable data layer (route +
`#card` + partials) with no page changes. Task 2 adds the client layer (`ui/_user_link` +
controller + the single Tailwind safelist edit), which needs Task 1's `user_card_path`. Tasks 3–5
wire render points in risk-ascending, file-disjoint batches — feed byline first because it fixes
real dead `"#"` links, then the standalone debate/notification/moderation surfaces, then the
already-linked swaps and the nested-anchor restructures last (the only HTML-validity hazard). Task
6 proves the JS end-to-end and runs the `bin/ci` gate. Each task ends with its own specs so the
per-task review checkpoint has something concrete to verify before the next begins.
