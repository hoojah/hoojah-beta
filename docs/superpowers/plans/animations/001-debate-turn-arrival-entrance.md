# 001 — Animate the arrival of a newly-posted debate turn

- **Status**: DONE (applied on master atop d903d72; 18 examples/0 failures)
- **Commit**: d903d72
- **Severity**: MEDIUM (missed opportunity — real-time content teleports)
- **Category**: 8. Missed opportunities (preventing a jarring change / spatial consistency)
- **Estimated scope**: 3 files, ~15 lines net. CSS + one conditional class + two locals.

## Problem

When a debate turn is posted, it is inserted into the transcript **instantly, with no
transition** — for the mover via the synchronous Turbo Stream response, and for the
opponent/spectator via an Action Cable `broadcast_append_later_to`. A chat-style bubble
just pops into existence at the bottom of the stack. This is the app's signature
real-time moment (a turn arriving *from another person over the wire*), and it is exactly
the "state change that teleports" that a brief entrance is meant to soften.

The turn row is appended here — synchronous path:

```erb
<%# app/views/debate_turns/create.turbo_stream.erb:4 — current %>
<%= turbo_stream.append dom_id(@debate, :transcript) do %>
  <%= render "debates/debate_turn", debate_turn: @turn, debate: @debate %>
<% end %>
```

…and here — async broadcast path (both participants subscribe to the debate stream; Turbo
dedups by `dom_id`, so whichever lands first inserts and the other is a no-op):

```ruby
# app/models/debate.rb:164 — current
broadcast_append_later_to self, target: dom_id(self, :transcript),
  partial: "debates/debate_turn", locals: {debate_turn: turn, debate: self}
```

The row element that gets appended:

```erb
<%# app/views/debates/_debate_turn.html.erb:50 — current %>
<div id="<%= dom_id(debate_turn) %>"
     class="debate-turn shadow px-3.5 py-3 max-w-[86%] <%= (side == :challenger) ? "self-start rounded-2xl rounded-bl-md bg-card" : "self-end rounded-2xl rounded-br-md bg-disagree-soft" %>">
```

**Critical constraint:** the SAME partial also renders every existing turn on first paint,
as a collection:

```erb
<%# app/views/debates/_debate_transcript.html.erb:14 — current (DO NOT make this animate) %>
<%= render partial: "debates/debate_turn", collection: turns, as: :debate_turn, locals: {debate: debate} %>
```

So the entrance must fire **only on append**, never on initial transcript load — otherwise
every turn animates on every page load, which is the "everything enters at once" anti-pattern
on content the user is trying to read. The mechanism below gates on an optional `entering:`
local that only the two append sites pass.

## Target

A calm rise-and-fade on the appended bubble only. `transform` + `opacity` only, under 300ms,
strong ease-out, reduced-motion drops the movement but keeps the fade.

Reuse the existing `hrise` **keyframe** (already in the bundle — the repo's entrance idiom is
keyframes, not `@starting-style`) but with a calmer curve than `.hrise`'s playful back-overshoot
(`.hrise` uses `cubic-bezier(.34,1.56,.64,1)`, correct for a composer expand, too bouncy for
debate content you read). New authored CSS in `app/assets/tailwind/application.css`, right after
the existing `.hrise` rule (line 379):

```css
/* target — app/assets/tailwind/application.css, after line 379 */

/* Entrance for a turn that ARRIVES after first paint — the synchronous post
   response and the Action Cable broadcast both add `debate-turn-enter` via the
   `entering:` local (debate_turns/create.turbo_stream.erb and Debate#post_turn).
   The transcript's first-paint collection render does NOT pass it, so existing
   turns never animate on load. Reuses the `hrise` keyframe (translateY(10px)+fade)
   with a calm ease-out instead of `.hrise`'s back-overshoot — this is content the
   reader is about to read, not a playful expand. */
.debate-turn-enter { animation: hrise 220ms cubic-bezier(0.23, 1, 0.32, 1); }

@keyframes hfade { from { opacity: 0 } to { opacity: 1 } }

@media (prefers-reduced-motion: reduce) {
  /* Keep the fade (it still signals "new"), drop the positional movement. */
  .debate-turn-enter { animation: hfade 200ms ease; }
}
```

The row gains the class only when appended:

```erb
<%# target — app/views/debates/_debate_turn.html.erb:50-51 %>
<div id="<%= dom_id(debate_turn) %>"
     class="debate-turn shadow px-3.5 py-3 max-w-[86%] <%= "debate-turn-enter" if local_assigns[:entering] %> <%= (side == :challenger) ? "self-start rounded-2xl rounded-bl-md bg-card" : "self-end rounded-2xl rounded-br-md bg-disagree-soft" %>">
```

And both append sites pass `entering: true`:

```erb
<%# target — app/views/debate_turns/create.turbo_stream.erb:5 %>
  <%= render "debates/debate_turn", debate_turn: @turn, debate: @debate, entering: true %>
```

```ruby
# target — app/models/debate.rb:164-165
broadcast_append_later_to self, target: dom_id(self, :transcript),
  partial: "debates/debate_turn", locals: {debate_turn: turn, debate: self, entering: true}
```

## Repo conventions to follow

- **Entrance animations are keyframe classes**, defined in `app/assets/tailwind/application.css`
  alongside the other `h*` keyframes (lines 366–372) and the `.hrise` class (line 379). Imitate
  `.hrise` exactly — same file, same shape, a class that sets `animation:` referencing an `h*`
  keyframe. Do NOT introduce `@starting-style` (it appears nowhere in this codebase).
- **This CSS file is not scanned by Tailwind as a source** (see the header comments in it and
  `CLAUDE.md` → "Tailwind gotchas"), so authored rules and comments here are safe and need no
  `@source inline`. `.debate-turn-enter` is hand-authored CSS, not a Tailwind utility.
- **Optional partial locals are read via `local_assigns[:key]`** — this is already the idiom in
  `ui/_menu.html.erb:44-45` (`local_assigns.fetch(:width)`, `local_assigns[:class]`). A collection
  render that doesn't pass the local yields `nil` → the `if` is false → no class. That is the whole
  gating mechanism; do not replace it with a different signalling scheme.
- `--ease-out` is inlined as a literal `cubic-bezier(...)` here rather than a token **only because
  a keyframe-`animation` shorthand cannot reference a CSS custom property for its easing in all the
  engines this app targets**; the value is the standard strong ease-out from the audit playbook.
  (Plan 002 introduces `--ease-out` as a real token for its `transition`-based use, where `var()`
  is fine.)

## Steps

1. In `app/assets/tailwind/application.css`, immediately after the `.hrise { … }` rule (line 379),
   add the three blocks from the Target section: `.debate-turn-enter`, `@keyframes hfade`, and the
   `@media (prefers-reduced-motion: reduce)` override. Keep the explanatory comment.
2. In `app/views/debates/_debate_turn.html.erb`, edit the opening `<div>` (line 50-51) to insert
   `<%= "debate-turn-enter" if local_assigns[:entering] %> ` into the class list, exactly as shown
   in Target. Leave everything else (the `id`, the `side` classes, the `dom_id` — LOAD-BEARING per
   the partial's own header comment) untouched.
3. In `app/views/debate_turns/create.turbo_stream.erb`, line 5, add `, entering: true` to the
   `render "debates/debate_turn", …` call. Do not touch the other three `turbo_stream.replace`
   blocks in that file.
4. In `app/models/debate.rb`, line 165, add `, entering: true` to the `locals:` hash of the
   `broadcast_append_later_to` call. Do not touch `broadcast_state_change`, `broadcast_to_each_participant`,
   or any other broadcast.

## Boundaries

- Do NOT add `entering:` to the collection render in `app/views/debates/_debate_transcript.html.erb:14`.
  If existing turns animate on page load, the gate has been broken — stop and re-check.
- Do NOT change the row's `id`/`dom_id`, the `.debate-turn-phase` span, the avatar, or any bubble
  colour/alignment class — the partial's header documents specs that anchor on each of those
  (`spec/system/debate_phases_spec.rb`, `spec/models/debate_broadcast_spec.rb`).
- Motion properties only. No markup restructure beyond adding the one conditional class token.
- Do NOT add an exit animation — turns are never removed from a transcript, so there is nothing to exit.
- No new dependencies, no `@starting-style`, no JS controller.
- If any cited line has drifted from the excerpt above (commit is no longer d903d72), STOP and report.

## Verification

- **Mechanical**:
  - `bundle exec standardrb app/models/debate.rb` → clean (the only `.rb` edit).
  - Build the bundle and confirm the new class shipped. The bundle is minified to one line, so
    count occurrences, not lines:
    `RAILS_ENV=test bin/rails tailwindcss:build`, then
    `grep -o 'debate-turn-enter' app/assets/builds/tailwind.css | wc -l` → `2` (the class + its
    reduced-motion override).
  - `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/debate_phases_spec.rb spec/models/debate_broadcast_spec.rb`
    → green (proves the `dom_id`, phase span, and broadcast locals still resolve).
- **Feel check**: run `bin/dev`, open a debate as two users in two browsers (or one browser + one
  incognito), and post a turn. Confirm:
  - On the **poster's** screen the new bubble rises ~10px and fades in over ~220ms — it does not pop.
  - On the **other** participant's screen the same bubble animates in when it arrives over the wire
    (no page reload).
  - **Reload the debate page**: the existing transcript appears instantly, with NO per-bubble
    animation. (If bubbles animate on load, Step 1/2's gate is wrong.)
  - In DevTools → Animations, set playback to 10% and post a turn; confirm a single clean rise+fade,
    not a double-fire (the sync + async dedup must yield exactly one animation).
  - In DevTools → Rendering, enable "Emulate prefers-reduced-motion: reduce" and post a turn: the
    bubble fades in but does not move.
- **Done when**: appended turns animate on both screens, initial load is static, reduced-motion drops
  the translate, and the two cited specs pass.
