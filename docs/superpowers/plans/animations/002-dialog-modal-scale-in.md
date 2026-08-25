# 002 — Scale-and-fade the shared native `<dialog>` modals on open

- **Status**: DONE (applied on master atop d903d72; modal system specs green)
- **Commit**: d903d72
- **Severity**: MEDIUM (missed opportunity — modal appears with no bridge)
- **Category**: 8. Missed opportunities + 3. Physicality & origin
- **Estimated scope**: 1 file (CSS only), ~18 lines. No markup, no JS.

## Problem

Every modal in the app is a native `<dialog>` opened with `showModal()` (see
`app/javascript/controllers/dialog_controller.js#open`). It appears **instantly** — the panel
and its backdrop both snap on with no transition. Three surfaces share this exact pattern and
all carry the same `data-dialog-target="dialog"` attribute:

```erb
<%# app/views/hujahs/_flag_dialog.html.erb:73 — current %>
  <dialog id="<%= dom_id(hujah, :flag_dialog) %>"
          data-dialog-target="dialog"
          data-action="click->dialog#backdropClose close->dialog#restoreFocus"
```

```erb
<%# app/views/hujahs/_challenge_dialog.html.erb:93 — current %>
  <dialog id="<%= dom_id(argument, :challenge_dialog) %>"
          data-dialog-target="dialog"
```

```erb
<%# app/views/users/_profile_edit.html.erb:64 — current %>
  <dialog id="<%= dom_id(user, :edit_dialog) %>"
          data-dialog-target="dialog"
```

Because all three share the attribute, **one CSS rule fixes all three journeys with no markup
change**. A modal snapping in gives no sense of where it came from; a brief scale-from-slightly-
smaller + fade is the standard, cheap way to make it feel like it grew into place rather than
teleported. Modals are an "occasional" surface (audit §1) → standard animation is warranted.

## Target

Panel scales `0.96 → 1` and fades `0 → 1`; backdrop fades in; both 200ms strong ease-out (within
the 200–500ms modal budget, audit §2). Entry only — see Boundaries for why exit is excluded.
`transform` + `opacity` only. Modals are **exempt from `transform-origin` at the trigger** (audit
§3) — they stay centered, which is the UA default, so we set no `transform-origin`.

This uses `@starting-style` (the correct tool for a `showModal()` entrance — the panel has no JS
mount hook to toggle a class, and `dialog_controller.js` must not be touched). Add to
`app/assets/tailwind/application.css` after the `.hrise` rule (line 379):

```css
/* target — app/assets/tailwind/application.css, after line 379 (or after plan 001's block) */

/* Modal entrance. All native <dialog>s in the app share `data-dialog-target="dialog"`
   (flag, challenge, profile-edit), so this one rule covers every modal with no markup
   change. showModal() flips display none→block and sets [open]; @starting-style supplies
   the first-frame values the transition animates FROM. Centered — modals do not scale
   from a trigger (audit: transform-origin at the trigger is for popovers, not modals). */
dialog[data-dialog-target="dialog"] {
  transition: opacity 200ms var(--ease-out), transform 200ms var(--ease-out);
}
dialog[data-dialog-target="dialog"][open] {
  opacity: 1;
  transform: scale(1);
}
@starting-style {
  dialog[data-dialog-target="dialog"][open] {
    opacity: 0;
    transform: scale(0.96);
  }
}
dialog[data-dialog-target="dialog"]::backdrop {
  transition: opacity 200ms var(--ease-out);
}
@starting-style {
  dialog[data-dialog-target="dialog"][open]::backdrop {
    opacity: 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  /* Keep the fade, drop the scale. */
  @starting-style {
    dialog[data-dialog-target="dialog"][open] { transform: none; }
  }
}
```

This requires the `--ease-out` token. Add it to the base `:root {` block (starts at line 299),
next to the other runtime tokens, **only if it is not already present** (plan 001 does not add it;
if plans are run in a different order this stays the single source):

```css
/* target — app/assets/tailwind/application.css, inside `:root {` (line 299) */
  --ease-out: cubic-bezier(0.23, 1, 0.32, 1); /* strong ease-out for UI transitions */
```

## Repo conventions to follow

- **All authored animation CSS lives in `app/assets/tailwind/application.css`**, after the `h*`
  keyframes / `.hrise` (lines 366–379). Put both the token and the dialog rules there.
- **This input CSS file is not scanned by Tailwind** (`CLAUDE.md` → "Tailwind gotchas": "The input
  CSS file is not scanned as a source at all, so its own comments are safe"), so no `@source inline`
  is needed and comments are free. Lightning CSS (Tailwind v4's engine) supports `@starting-style`.
- **Design tokens are CSS custom properties in `:root {`** (line 299) and its `[data-theme]` /
  `[data-scheme]` overrides. `--ease-out` is theme-independent, so it belongs in the **base**
  `:root {` block only — do NOT duplicate it into the dark/scheme blocks.
- The dialog behaviour contract is documented at the top of `dialog_controller.js`; this plan does
  not touch it. `showModal()` (not `show()`) is what makes `[open]` + `::backdrop` exist, which is
  what the `@starting-style` rule keys on.

## Steps

1. In `app/assets/tailwind/application.css`, inside the base `:root {` block (starts line 299),
   add `--ease-out: cubic-bezier(0.23, 1, 0.32, 1);` alongside the other tokens — unless it is
   already defined there (plan 001 may have been applied; it does not add this token, but check).
2. In the same file, after the `.hrise { … }` rule (line 379) — or after plan 001's
   `.debate-turn-enter` block if that plan landed first — add the full dialog block from Target:
   the base `transition`, the `[open]` target, the two `@starting-style` rules (panel + backdrop),
   and the `prefers-reduced-motion` override. Keep the comment.
3. Nothing else. No `.erb`, no `.js`, no markup changes.

## Boundaries

- Do NOT edit any `.erb` partial or `dialog_controller.js`. This is CSS-only; the shared attribute
  is the entire seam.
- Do NOT add an **exit** animation. Animating a native `<dialog>` close needs
  `transition-behavior: allow-discrete` on `display`/`overlay`, which is finicky and less-supported;
  an enter-only scale-in with an instant close is a deliberate, common, low-risk choice here and
  matches the app's "essentially no animation" restraint. If you think exit is wanted, that is a
  SEPARATE plan — do not fold it in.
- Do NOT set `transform-origin` — modals stay centered (audit §3 explicitly exempts them).
- Do NOT scope the rule more tightly than `data-dialog-target="dialog"`; scoping to individual ids
  would miss two of the three modals and is the thing this plan deliberately avoids.
- No new dependencies. If the `--ease-out` token already exists, do not add a second copy.
- If the cited dialog attributes or the `:root` block have drifted from the excerpts above (commit
  no longer d903d72), STOP and report.

## Verification

- **Mechanical**:
  - Build and confirm the rule shipped. NOTE: the built bundle is **minified to one line** and
    Lightning CSS **strips the quotes from attribute selectors** (`data-dialog-target=dialog`), so
    `grep -c` (line count, quoted) is useless here — it returns 0/1 regardless. Count occurrences
    on the unquoted pattern instead:
    `RAILS_ENV=test bin/rails tailwindcss:build`, then
    `grep -o 'data-dialog-target=dialog' app/assets/builds/tailwind.css | wc -l` → `6`
    (base + `[open]` + `@starting-style` panel + `::backdrop` + `@starting-style` backdrop +
    reduced-motion), and
    `grep -o 'starting-style' app/assets/builds/tailwind.css | wc -l` → `3`.
  - `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system --tag js -e dialog` (or the flag /
    challenge / profile-edit system specs) → green: the open/close/backdrop/Esc behaviour is
    unchanged (this plan only adds motion, so every existing modal spec must still pass).
- **Feel check**: run `bin/dev` and open each modal — the **flag** menu on a hujah, **Challenge** on
  an argument, **Edit profile** on your own profile. Confirm:
  - The panel grows from 96% to 100% and fades in over ~200ms, centered — it does not slide from a
    corner and does not pop.
  - The backdrop fades in with it rather than snapping to full opacity.
  - Closing (button, Esc, backdrop click) still works and closes immediately — no half-open state.
  - In DevTools → Animations, set playback to 10% and open a modal: confirm a single smooth
    scale+fade, and that focus still lands correctly inside the dialog (the controller's focus
    handling must be unaffected).
  - In DevTools → Rendering, enable "Emulate prefers-reduced-motion: reduce": the modal fades in but
    does not scale.
- **Done when**: all three modals scale-and-fade in, close behaviour and focus are unchanged, the
  existing modal system specs pass, and reduced-motion drops the scale.
