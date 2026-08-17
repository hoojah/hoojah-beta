# Task 4.6 (forms family, commit a410be7) — retroactive freeze audit

**VERDICT: CLEAN.** No freeze violations.

Method: stripped every `class="…"` / `class: "…"` / `class: ds_button_classes(…)` and every ERB
comment from both sides of all ten files, then diffed the residue. That residue IS the complete
non-`class` change set — nothing was eyeballed.

## Non-class change set (all adjudicated ALLOWED)

1. `sessions/new`, `registrations/new`, `passwords/new`, `passwords/edit` — outer styled `<div>` →
   `render layout: "ui/card"` block. Same emitted `<div>`, same utilities minus `rounded`.
   `padded:` deliberately not passed, so no padding collision.
2. `confirmations/new`, `unlocks/new`, `registrations/edit` — bare `<h2>` gains a class; page
   wrapped in `ui/_card`. Text nodes byte-identical.
3. Same three files — `<div class="field"><p>label</p><p>field</p></div>` → `<div class="mb-3">`.
   `<p>` elements removed. `.field` / `.actions` have NO CSS rule anywhere in the repo and NO spec
   selects them (verified). Labels still `f.label`, so `for=`/`id=` binding intact.
4. `registrations/edit` — two `<i>` → `<em>`. Text byte-identical.
5. `registrations/edit` — `<p><em>N characters minimum</em></p>` → bare `<em>`. Copy identical.
   The pre-existing parenthesisation inconsistency vs. `registrations/new` was preserved, correctly.
6. `registrations/edit:69` — ADDED `render "ui/divider", class: "my-6"`. Emits `border-t
   border-gray-100` in a `<div>`, not an anchor.
7. `registrations/edit` — "Unhappy?" text node whitespace one-space → newline+indent inside a new
   flex container. Rendered string unchanged; `gap-2` supplies the 8px.
8. `registrations/edit` — ADDED a `max-w-md mx-auto mt-6 text-sm` wrapper around `link_to "Back",
   :back`, still OUTSIDE the card block. `:back` untouched.
9. `shared/_links` — body wrapped in `mt-6 flex flex-col gap-1 text-sm`. All six branch conditions,
   six `link_to` URLs, the omniauth `button_to` path and its `data: {turbo: false}` byte-identical.
   No double-wrap: the four callers that supplied their own wrapper dropped it in the same commit.
10. `shared/_error_messages` — `id="error_explanation"` + `data-turbo-temporary` both intact; pure
    line-break to fit the added class.
11. `render "devise/shared/links"` moved into the card block. Same partial, no locals.
12. `users/_profile_edit` — **zero non-class differences.**

## Point verdicts

- Field names / `f.<field>` — identical, machine-diffed per file.
- `form_with`/`form_for`/`button_to` url + `method:` — inventory identical (1 delete, 1 patch,
  3 post, 2 put; same seven path helpers).
- `invisible_captcha :subtitle` — a diff CONTEXT line, never touched; still third statement in the
  form, still outside every field wrapper.
- User-visible strings — zero differences. Every submit label, heading, hint, link label,
  `aria-label` and all five placeholders round-trip.
- `dom_id` / explicit `id=` — unchanged; none added or removed.
- `data-*` — none added, removed, renamed or reordered.
- `autocomplete` ×14 / `autofocus` ×7 / `type="button"` ×3 / `rows: 3` / 5 placeholders — byte-
  identical. All 8 `f.password_field` present on both sides; no password field downgraded to text.

## Hazard checks

- **Interpolated Tailwind class with no `@source inline`: CLEAR.** The only interpolation inside a
  `class` attribute is `ds_button_classes(size: :sm)`; every token it can emit here is safelisted.
  `focus:border-primary` confirmed present in the compiled bundle.
- **Uncoloured `border-*` inside an `<a>`: CLEAR.** Every border added is colour-paired or
  zero-width, and no anchor in the family carries any `class` at all.

## Looks-like-a-defect, isn't

- `fill-white` dropped from the profile-edit pencil trigger — was already a no-op (class sat on the
  `<button>`, `fill="none"` is on the `<svg>`). Same dead `fill-white` still at
  `users/_profile_header.html.erb:22`. (Now covered by the repo-wide strip.)
- `border-0` dropped from `f.submit` — preflight already zeroes input borders.
- `inline-flex` on `<input type="submit">` — third family to do it; `_compose_form` (4.3) and
  `_turn_composer` (4.5) shipped it first. Precedent, not drift.

## Its one claimed defect was a FALSE POSITIVE — do not act on it

The auditor claimed `devise/registrations/new.html.erb`'s header comment names the wrong owner for
strong-param sanitisation, asserting `Users::RegistrationsController` contains only
`invisible_captcha`. **Verified false.** That controller has, at HEAD and at `a410be7` alike:

    before_action :configure_permitted_parameters
    def configure_permitted_parameters
      devise_parameter_sanitizer.permit(:sign_up, keys: [:username, :full_name])
      devise_parameter_sanitizer.permit(:account_update, keys: [:username, :full_name])
    end

The comment is accurate. No edit required.

## Stale-artifact note

`app/assets/builds/tailwind.css` is gitignored; the auditor's local copy predated the commit by
83 minutes. It used the file only to confirm rules that already existed, never to prove absence.

---

# PASTE-READY VISUAL DELTA LIST (the artifact Task 4.6 never wrote)

```
Visual deltas, Slice 9 Task 4.6 (forms family). Markup/class only; the
per-element freeze diff for this commit is clean — see the audit note below.

app/views/devise/sessions/new.html.erb
  The panel loses its corner radius: the hand-typed `bg-white rounded shadow`
  becomes `ui/_card`, whose CARD_BASE is `shadow bg-white` with no rounding and
  no way to ask for one — Card.prompt.md's first line is "Never round a feed
  card". Both inputs stop being outlined in body ink: they carried a bare
  `border`, and Tailwind v4 resolves an uncoloured border to `currentColor`, so
  they now take `border-gray-200` (the --border-field token, readme "Colors")
  plus `focus:border-primary`. Labels go from 16px ink to 14px grey
  (`text-sm text-grey`, readme "Type": UI text 14px). "Remember me" becomes a
  16px native checkbox (`w-4 h-4`) with a 14px grey label — Checkbox.prompt.md
  verbatim. The submit changes from a hand-typed `bg-primary rounded px-4 py-2`
  to ds_button_classes(variant: :rect): same 16px type, padding 16px -> 20px
  horizontal, and it gains `cursor-pointer` and `active:scale-95`. readme
  "Buttons": "Rect `rounded` solid buttons on auth screens"; Button.prompt.md's
  own example is literally `<Button variant="rect">Log in</Button>`.

app/views/devise/registrations/new.html.erb
  Same five deltas as log-in: square card, five fields off currentColor onto
  the field-border token with an indigo focus border, 14px grey labels, and the
  `rect` submit for "Sign up" (readme "Buttons" names the signup CTA
  explicitly). The password-length hint moves off Tailwind's `text-gray-500`
  onto `text-grey` (#8e8e8e, the palette's only muted grey). No "@" prefix and
  no placeholders were added to the username field even though
  TextField.prompt.md shows both — this screen has never rendered them and they
  would be new user-visible copy. `invisible_captcha :subtitle` is untouched and
  still sits outside every field wrapper.

app/views/devise/registrations/edit.html.erb
  The largest visual change in the family: this screen had NO styling at all —
  bare `<h2>`, paragraph-wrapped fields, `.field`/`.actions` wrappers with no
  rule behind them — so it rendered as browser defaults on white while every
  sibling was a card. It now takes the full auth treatment: `ui/_card`, a 24px
  semibold heading (--text-2xl, commented in application.css as "auth screen
  headings"), 14px grey labels, four fields on the field-border token with the
  indigo focus border, and the `rect` submit. Devise's two parenthetical hints
  move from inline `<i>` after the label to their own 12px grey `<em>` line
  below it, because the label is now `block` (readme "Type": micro-labels 12px).
  The account-deletion block is separated by `ui/_divider` (border-gray-100,
  --border-hairline) rather than a second card — Card.prompt.md: internal
  sections take the rule, never a nested surface. "Cancel my account" goes from
  an unstyled browser button to ds_button_classes(tone: "neutral", size: :sm) —
  the neutral-stance pink the product already uses for report/flag, kept
  distinct from the error red that FormError.prompt.md reserves for validation.
  Its confirm/turbo_confirm attributes and DELETE verb are unchanged. "Back"
  gains a 14px container aligned to the card's own max-width.

app/views/devise/passwords/new.html.erb
  Square card, one field off currentColor onto the field-border token with the
  indigo focus border, 14px grey label, and "Send me password reset
  instructions" on the `rect` solid button.

app/views/devise/passwords/edit.html.erb
  Square card, both password fields on the field-border token with the indigo
  focus border, 14px grey labels, the length hint off Tailwind grey onto
  `text-grey`, and "Change my password" on `rect`. The hidden
  reset_password_token field is untouched.

app/views/devise/confirmations/new.html.erb
  Was entirely unstyled — a bare `<h2>` and Bootstrap-era `.field`/`.actions`
  wrappers matching no rule in the bundle. Now the shared auth treatment: card,
  24px heading, one labelled field on the field-border token with the indigo
  focus border, `rect` submit. Not reachable today (User is not :confirmable),
  restyled so switching the module on cannot land an unstyled screen.

app/views/devise/unlocks/new.html.erb
  Identical treatment and identical rationale to the confirmations screen; not
  reachable today (User is not :lockable).

app/views/devise/shared/_error_messages.html.erb
  This partial carried no classes at all, so on every Devise form the validation
  summary rendered as bare black body text and read as page content rather than
  as a failure. It becomes the red-tinted panel the profile dialog already spelt
  by hand: `bg-red-50 text-red-700 text-sm` in a rounded box, bulleted list,
  medium-weight heading inheriting 14px from the panel because preflight strips
  the browser's own h2 size. FormError.prompt.md: "the validation summary at the
  top of a form — the only place red appears in Hoojah". `id="error_explanation"`
  and `data-turbo-temporary` are unchanged.

app/views/devise/shared/_links.html.erb
  The link stack now owns its own box instead of relying on the caller. Four of
  the six auth views wrapped this render in an identical `mt-4 text-sm` div and
  two did not, so those two showed 16px links hard against the form; all six now
  get `mt-6 flex flex-col gap-1 text-sm`. The gap is explicit because preflight
  zeroes paragraph margins, so the rows would otherwise sit flush. No colour
  class: @layer base already paints every anchor with --fg-link. Every branch
  condition, URL and label is unchanged.

app/views/users/_profile_edit.html.erb
  Already the family's most conformant screen; four deltas. The pencil trigger
  drops two dead Bootstrap class names (`btn btn-link` — no rule exists for
  either anywhere in the bundle) for what they were pretending to be: a bare,
  borderless, transparent control, plus an explicit `cursor-pointer` that
  Tailwind v4 no longer gives buttons. All five fields gain the indigo focus
  border of TextField/TextAreaField; they already had the correct border colour,
  which is what the auth screens lacked. "Update photo" goes through
  ds_button_classes(size: :sm) — visually the same outline pill, now at 14px
  instead of inherited 16px, which corrects pre-existing drift the helper
  documents. "Save changes" goes through ds_button_classes(variant: :solid) —
  the solid pill readme "Buttons" and Button.prompt.md both name by that exact
  label — gaining ~4px horizontal padding and `active:scale-95`. The dom_id,
  the PATCH, every data-*, every placeholder and every aria-label are byte-
  identical: this file's non-class diff is empty.

AUDIT NOTE (closing the gap this commit disclosed): the per-element freeze diff
was run retrospectively by stripping all class attributes and ERB comments from
both sides of all ten files and diffing the residue. The residue is limited to
container swaps onto ui/_card, removal of unstyled <p>/.field/.actions wrappers,
two <i>-><em> swaps, one added ui/_divider, and two added layout <div>s. All
form field names, form URLs and verbs, autocomplete/autofocus/type/rows/
placeholder attributes, dom_ids, explicit ids, data-* attributes and every
user-visible string are byte-identical. invisible_captcha :subtitle is intact
and correctly positioned. No interpolated class escapes the @source inline
safelist; no uncoloured border exists in this family, and no anchor in it
carries any border at all.
```
