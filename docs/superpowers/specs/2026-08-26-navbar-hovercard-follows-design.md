# Design: Navbar rearrange · User hovercard · Follow-system gaps — 2026-08-26

Three independent sub-projects (slices), designed together because they share the
social/identity surface. Each ships as its own plan → subagent-driven implementation →
`bin/ci`. **Build order: A (navbar) → C (follows) → B (hovercard)** — B consumes the count
methods C introduces and the existing follow button.

Owner decisions (locked): navbar hides New Claim for guests; hovercard covers **all** user
render points; card content is **Standard** (private users get the gated minimal set); follow
gaps = **Everything** (incl. the counter-cache, flagged high-risk).

Research grounding (confirmed file:line references) is inlined per slice so implementers don't
re-derive it.

---

## Slice A — Navbar 3-zone rearrange

### Goal
Desktop navbar becomes three zones: **left** = accessibility toggles + user dropdown, **center**
= logo, **right** = actions (New Claim for logged-in / Login+Sign up for guests; Trending on
mobile only). Mobile (<sm) keeps the current logo-left layout.

### Current state
`app/views/shared/_navbar.html.erb` — inner bar (line 28) is
`max-w-xl sm:max-w-none mx-auto px-4 sm:px-6 h-14 flex items-center justify-between` with exactly
two flex children: the logo (lines 29–31, LEFT) and one `div.flex.items-center.gap-3` (line 33,
RIGHT) holding theme pill (41–50), Trending (`lg:hidden`, 55–58), the `user_signed_in?` branch
(60–125: logged-in `<details>` avatar dropdown / guest Login+Sign up text links), and New Claim
(127–130, currently rendered for BOTH guests and members). Accessibility = one `theme` Stimulus
controller with `toggleTheme` + `cycleScheme` actions.

### Design
- **Container:** three real children in DOM order — LEFT group, CENTER logo, RIGHT group.
  - Mobile (<sm): `flex items-center justify-between` — logo needs to read left, so on mobile the
    LEFT group (a11y + user) and RIGHT group flank it; to keep the current "logo-left" feel the
    implementer may use flex `order` utilities so the logo sits first on mobile. Acceptable
    alternative if ordering proves fiddly: on mobile show logo-left + a single right group
    (a11y/user/actions) — the key constraint is mobile must not regress to a broken layout.
  - Desktop (≥sm): `sm:grid sm:grid-cols-3` with `sm:justify-self-start` / `-center` / `-end` on
    the three groups so the logo is **truly centered** regardless of side widths.
- **LEFT group:** theme pill (unchanged markup, 41–50) + the `<details>` user dropdown (64–121)
  **only when `user_signed_in?`**. Guests: left group is just the theme pill.
- **CENTER:** the logo link (29–31), unchanged markup.
- **RIGHT group:**
  - Trending link (55–58) keeps `lg:hidden` (mobile/tablet only).
  - Logged-in: New Claim (127–130).
  - Guest: Login + Sign up text links (122–125). **New Claim is NOT rendered for guests** (move it
    inside the `user_signed_in?` branch).
- All classes are literal in ERB → **no new Tailwind `@source inline` safelist entries**.

### Acceptance
- ≥sm: logo centered; a11y(+user) flush left; actions flush right; no horizontal overflow.
- Guest ≥sm: left = a11y only; right = Login + Sign up; **no New Claim anywhere**.
- Logged-in ≥sm: left = a11y + avatar dropdown; right = New Claim.
- <sm: logo reads left; Trending visible; layout not regressed.
- Existing navbar/dropdown behavior (theme toggle, scheme cycle, unread dot, menu links, logout)
  unchanged.

### Tests
Request/system smoke that renders the layout signed-in AND signed-out (no ERB error; New Claim
absent for guests, present for members; Login/Sign up absent for members).

---

## Slice C — Follow-system gaps (Everything)

### Current state (works today)
`Follow` join (`app/models/follow.rb`, schema.rb:111–121): `follower_id`, `followed_id`,
`status` enum `{pending:0, accepted:1}` (DB default pending), unique `[follower_id, followed_id]`,
DB `no_self_follow` check. `User` (user.rb:11–22): `active_follows`/`passive_follows` (all
statuses), `following`/`followers` **accepted-only** through-scopes. Counts are computed
(`.followers.size`/`.following.size`), no counter cache. Controllers: `follows#create` (status =
private? pending : accepted; idempotent, rescues RecordNotUnique), `follows#destroy` (unfollow +
cancel-pending), `follow_requests#update` (accept), `follow_requests#destroy` (decline). Routes
routes.rb:66–76. Notifications: `new_follower:6`, `follow_request:12`, `follow_accepted:13`,
created in `Follow`. Block removes follows both directions via `delete_all`
(blocks_controller.rb:6–18). Private→public bulk-accepts pending via `update_all`
(users_controller.rb:52–57). Policies correct (FollowPolicy, FollowRequestPolicy).

### Gaps to fill (all)
1. **Pending-requests inbox.** New `follow_requests#index` + `GET /follow_requests`; lists the
   signed-in user's pending `passive_follows` (requester via `_user_row`) with Accept/Decline
   controls; empty state via `ui/empty_state`; `policy_scope`/`skip_authorization` consistent with
   other own-resource surfaces. Link it from the user dropdown (a "Follow requests (N)" row, count
   = pending passive follows) and keep the inline notification-card actions working. Gated to the
   owner by construction.
2. **Remove-follower.** New action + route `DELETE /u/:username/follower` →
   `follows#remove_follower` (or `follows#destroy_follower`). Destroys the accepted `Follow` where
   `followed = current_user` and `follower = :username`'s user. Policy: only the followed user may
   remove. "Remove" control on the followers list `_user_row` (surface-gated so it shows only on
   the owner's own followers page). Turbo response updates the row + follower count.
3. **Turbo-ify Accept/Decline.** `follow_requests#update`/`#destroy` respond with `turbo_stream`
   (update/remove the request row + counts) instead of `redirect_back`. Keep the notification-card
   Accept/Decline working (they target the same partials).
4. **Cancel-pending dismisses notification.** `FollowsController#destroy`, when the destroyed row
   was pending, calls the same `dismiss_request_notification` logic used by
   `follow_requests#destroy` so the target's "requested to follow you" card clears.
5. **Bulk private→public side effects.** Replace `users_controller.rb:57`'s
   `passive_follows.pending.update_all(status: :accepted)` with a path that, per accepted request,
   fires `follow_accepted` (to requester) + `new_follower` (to the now-public user) + badge awards
   — the same effects as accepting one-by-one. For large sets, enqueue a job
   (`AcceptPendingFollowsJob`) to avoid a slow request; small sets may run inline. Counts (gap 8)
   must update for every accepted row.
6. **Stale-request expiry.** `ExpireStaleFollowRequestsJob` (recurring via `config/recurring.yml`,
   mirroring `ConcludeStaleDebatesJob`): destroys pending follows older than **30 days**. Dismisses
   the associated request notification. No notification to the requester (matches decline's
   "no blast" convention). Decrement no counts (pending never counted).
7. **Unfollow confirmation.** Add `data-turbo-confirm: "Unfollow @username?"` to the "Following"→
   unfollow `button_to` in `_follow_button.html.erb` (accepted state only; "Requested"/cancel does
   not need a confirm). System spec updates to accept the confirm dialog.
8. **Counter-cache (HIGH RISK).** Add `followers_count` and `following_count` integer columns to
   `users` (default 0, null: false). Maintained by explicit `Follow` model logic — **NOT** Rails'
   built-in `counter_cache:` (which would count pending rows too; our counts are accepted-only).
   Every mutation path must keep both sides in sync:
   - **Accept transition** (pending→accepted, and create-as-accepted for public): +1 followed's
     `followers_count`, +1 follower's `following_count`.
   - **Unfollow / remove-follower / destroy of an ACCEPTED row:** −1 each side.
   - **Decline / cancel of a PENDING row:** no change (pending never counted).
   - **Block's `delete_all`** (blocks_controller.rb) skips callbacks → adjust the two counts
     explicitly inside that transaction for any accepted rows deleted.
   - **Bulk private→public accept** (gap 5): increment counts for every accepted row.
   Implement via a single well-tested method (e.g. `Follow#adjust_counter_caches(direction)` called
   from the accept/destroy paths, plus explicit adjustment in the block transaction). Backfill with
   a `strong_migrations`-safe migration: add columns with default 0, then backfill in batches
   (`in_batches`) from the accepted-only scopes; wrap the count updates so they can't drift.
   Move all reads (`_follower_count.html.erb:6`, `_profile_header.html.erb:138`,
   `_gated_header.html.erb`, `analytics_controller.rb:18`, and Slice B's card) to
   `user.followers_count` / `user.following_count`. Add a `rake`/spec-guarded consistency check
   comparing the columns to the live scopes to catch drift during development.

### Policies / privacy
Reuse existing FollowPolicy / FollowRequestPolicy. Remove-follower authorized only to the
followed user. Inbox scoped to owner. Private + block semantics unchanged.

### Tests
Extend `spec/models/follow_spec.rb`, `spec/requests/follow_spec.rb`,
`spec/requests/follow_request_spec.rb`, `spec/system/follow_spec.rb`, `private_spec.rb`,
`block_spec.rb`. New: `follow_requests#index` request+system, remove-follower request+system,
counter-cache model specs covering EVERY mutation path (accept, unfollow, remove, decline, block,
bulk private→public, expiry job), the expiry job spec, and a drift check.

---

## Slice B — User hovercard + click-to-profile everywhere

### Goal
Hovering any user's avatar / @username / full name shows a small profile card (Standard fields;
private strangers get the gated minimal set). Clicking opens `/u/:username`. Applies to **all**
user render points.

### Current state
No hover/tooltip/popover infrastructure exists. `ui/_avatar` renders the visual box only (no
link). Only 4 surfaces link users to profiles today (`_user_row`, `search/_result_user`,
notification "View profile", navbar). **High-traffic surfaces are unlinked** — the feed byline
avatar + name link to literal `"#"` placeholders (`_hujah_header.html.erb:59,63`); hujah show
(77–81), reply/child cards (43–47), debate views, and trending `@username` are plain text.
Profile route `get "/u/:username" ... as: :profile` (routes.rb:60); users addressed by the
`username` column directly (no friendly_id). Standard-field data on `User`: `full_name`,
`username`, `headline`, `location`, `link`, avatar (`ds_avatar_url`), `private`, badges,
follower/following counts. `visible_to?(viewer)` is the single privacy gate; `_gated_header`
is the private-account whitelist template. Lazy-load precedent: `turbo_frame_tag ... src:
loading: :lazy`. Reusable overlay lifecycle reference: `dialog_controller.js`
(open/close/teardown on Turbo cache); debounce reference: `search_controller.js`.

### Design
- **`ui/_user_link` layout partial.** `render layout: "ui/user_link", locals: {user:, class:} do …
  end` → emits `<a href="<%= profile_path(user.username) %>" class="… no-underline"
  data-controller="hovercard" data-hovercard-username-value="<%= user.username %>"
  data-hovercard-url-value="<%= user_card_path(user.username) %>"
  data-action="mouseenter->hovercard#scheduleShow mouseleave->hovercard#scheduleHide
  focusin->hovercard#scheduleShow focusout->hovercard#scheduleHide">…block…</a>`. Wrap the
  avatar and the name/username at each render point with it (replacing the dead `"#"` links and
  adding links where missing). Keep it a genuine anchor so keyboard/click and no-JS both work.
- **`hovercard_controller.js` (new Stimulus).**
  - Values: `username:String`, `url:String`. Class-level shared cache (username → HTML) so repeat
    hovers don't refetch.
  - `scheduleShow`: after ~400 ms `fetch(url)` (once; cache), inject the returned partial into a
    single shared floating panel element appended to `<body>`, position it near the trigger
    (viewport-aware: flip above/below, clamp horizontally), fade in. The panel itself listens for
    `mouseenter`/`mouseleave` so moving cursor from trigger → card keeps it open.
  - `scheduleHide`: hide after a short grace (~200 ms) unless the pointer is over trigger or card.
  - Dismiss on scroll, `Escape`, click-away, and `turbo:before-cache` (teardown like
    `dialog_controller`).
  - **Touch:** if `matchMedia('(pointer: coarse)').matches`, do nothing on hover — the link click
    just navigates. No card on touch.
- **Card endpoint.** `GET /u/:username/card` → `UsersController#card` (or `UserCardsController#show`),
  `skip_authorization`, `render "users/hovercard", layout: false`. Gated via
  `@user.visible_to?(current_user)`: visible → Standard partial; gated → minimal partial
  (avatar, name, @handle, "Private account", Follow button, counts). Read-only → **main route,
  not `Api::V1`** (CSRF/`verify_authorized` convention). Guests may view public cards.
- **`users/_hovercard.html.erb`.** Standard content: `_avatar` (size ~md), full name, `@username`,
  `headline`, follower + following counts (via C-8's `followers_count`/`following_count`), and
  `_follow_button` (hidden for self / guests as that partial already handles). Panel styled like
  the `ui/_menu` surface (white, `shadow`, rounded). Any new interpolated/position classes → add
  `@source inline(...)`; prefer literal classes.

### Render points to convert (all)
Feed byline `_hujah_header.html.erb:46–65` (kill the `"#"` links); hujah show
`show.html.erb:77–81`; replies `_child_card.html.erb:43–47`; debates
(`_debate_pending`, `_debate_scoreboard`, `_debate_turn`, `_verdict`, `debates/new`);
notifications `_notification_card.html.erb:86`; search `_result_hujah` `@username`; trending
`_trending.html.erb:29`; profile/`_user_hujah`; moderation `_flagged_hujah`. Already-linked
surfaces (`_user_row`, `_result_user`, navbar) gain the hovercard triggers on their existing
links. Do this via `ui/_user_link` for consistency; note per-surface layout differences (some
wrap avatar+name together, some separately).

### Acceptance
- Hovering avatar/name/@username on any surface shows the card after a short delay; moving onto the
  card keeps it open; leaving hides it; Escape/scroll/click-away dismiss.
- Clicking navigates to `/u/:username` on every surface (no more `"#"`).
- Private stranger's card = gated minimal; public = Standard; guest can view public cards.
- Touch devices: tap navigates, no card. No-JS: links still work, no card.
- No Tailwind orphan rules; md5 bundle check on comment-only edits.

### Tests
Request specs for `#card` (public Standard, private gated, guest allowed, 404 unknown username);
system specs (hover shows card, click navigates, private gating) tagged `js: true`; a spec
asserting the feed byline links now point to `profile_path` (not `"#"`).

---

## Cross-cutting notes
- StandardRB, Brakeman, bundler-audit, prosopite discipline per CLAUDE.md; `bin/ci` green per
  slice. Shared Postgres test DB → run suites one at a time.
- No Claude/Anthropic branding in commits. Commit subjects: plain imperative (these are not
  numbered roadmap slices).
- Tailwind v4 gotchas apply (ERB comments are scanned; interpolated classes need `@source
  inline`); the only likely new safelist entries come from Slice B's hovercard positioning/panel.
- Deferliness: the counter-cache (C-8) is the one piece the owner may still choose to drop; the
  rest of C does not depend on it if reads stay on `.size` (B would then use `.size` too).
