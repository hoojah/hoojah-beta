# Upload fix + UI polish — implementation plan

Four self-contained tasks. Research is complete; file/line references below were verified against
the working tree at planning time. Do the simplest thing that works — no scope beyond these four.

## Ground rules (apply to every task)

- **StandardRB** formats all Ruby (`bundle exec standardrb --fix` before committing).
- **Pundit**: no task adds a controller action, so there is nothing new to `authorize` — but the
  Task 1 request spec must hit an existing public action (root feed) that already calls
  `skip_authorization`/`authorize`.
- **Tailwind**: every class added below is a **literal string in ERB or a Ruby string literal**,
  both of which the scanner extracts — so **no new `@source inline(...)` entries are required**.
  Do NOT introduce any interpolated hover/stance utility (e.g. `hover:bg-#{tone}-soft`); if you
  find yourself wanting one, stop and use a colour-independent effect instead.
- Motion: `--ease-out: cubic-bezier(0.23, 1, 0.32, 1)` already exists on the unlayered `:root`
  (application.css:359) and the global `prefers-reduced-motion` guard (application.css:140)
  neutralises all transition durations app-wide — **no per-rule reduced-motion handling needed**.
- Commit subjects: plain imperative, one commit per task, **no Claude/Anthropic branding**
  (no `Co-Authored-By`, no "Generated with").

## Sequencing

| Task | Files touched | Parallel-safe with |
|---|---|---|
| 1 CSP | `config/initializers/content_security_policy.rb`, new `spec/requests/content_security_policy_spec.rb` | 2, 3, 4 |
| 2 Modal centering | `app/assets/tailwind/application.css` (modal block ~451–501), `app/views/hujahs/_add_image_dialog.html.erb` | 1, 3, 4 |
| 3 Motion pass | `app/helpers/design_system_helper.rb`, `app/views/hujahs/_response_filter.html.erb`, `app/views/hujahs/_compose_form.html.erb`, `spec/helpers/design_system_helper_spec.rb` | 1, 2, 4 |
| 4 Visibility icon | `app/helpers/icons_helper.rb`, `app/views/hujahs/_hujah_header.html.erb`, `app/views/users/_user_hujah.html.erb`, `spec/helpers/icons_helper_spec.rb`, `spec/views/users/_user_hujah_spec.rb` | 1, 2, 3 |

The four file sets are **disjoint — all four can run in parallel**. Practical order: start
Task 1 (production upload is broken, smallest diff) and Task 2 (needs a live browser for
root-causing) first; Tasks 3 and 4 alongside. **Integration is serial**: after all four land,
one agent runs `bundle exec standardrb` then `bin/ci` (remember: one test-suite run at a time —
shared Postgres test DB).

---

## Task 1 — Fix hujah image upload (CSP)

**Root cause (confirmed, do not re-diagnose):** production serves Active Storage via the S3
service `garage` at `ENV.fetch("GARAGE_ENDPOINT", "https://s3-grg.novas.my")` (config/storage.yml:40).
Two CSP violations in `config/initializers/content_security_policy.rb`:
(a) `img_src` blocks the `blob:` preview from `URL.createObjectURL`
(image_upload_controller.js:84-85, 177); (b) `connect_src` blocks the direct-upload PUT to the
garage host (image_upload_controller.js:88). Displayed images go through the Active Storage
**proxy** (same-origin), so the garage host must NOT be added to `img_src` — only `:blob`.

### Changes — `config/initializers/content_security_policy.rb`

Replace lines 12–13 with (keeping the file's heavy-comment style — yes, add the comments,
this file explains every host it names):

```ruby
    # blob: — the composer's client-side image preview: image_upload_controller
    # renders the picked file via URL.createObjectURL before/while the upload runs.
    # Attached images themselves are served SAME-ORIGIN through the Active Storage
    # proxy (ds_hujah_image_url / ds_avatar_url), so the garage host deliberately
    # does NOT appear here.
    policy.img_src :self, :data, :blob, "https://res.cloudinary.com", "https://*.drift.com"
    # The garage host: Active Storage direct uploads PUT straight from the browser
    # to a presigned URL on the S3/Garage endpoint. Same ENV expression as
    # config/storage.yml so the two can never drift.
    policy.connect_src :self, "https://*.drift.com", "wss://*.drift.com",
      ENV.fetch("GARAGE_ENDPOINT", "https://s3-grg.novas.my")
```

### New spec — `spec/requests/content_security_policy_spec.rb`

```ruby
require "rails_helper"

RSpec.describe "Content Security Policy", type: :request do
  it "permits blob: image previews and the garage direct-upload host" do
    get root_path
    expect(response).to have_http_status(:ok)
    csp = response.headers["Content-Security-Policy"]
    expect(csp[/img-src[^;]*/]).to include("blob:")
    expect(csp[/connect-src[^;]*/])
      .to include(ENV.fetch("GARAGE_ENDPOINT", "https://s3-grg.novas.my"))
  end
end
```

If `root_path` doesn't 200 anonymously in test, use any public GET that does (check
`spec/requests/hujahs_index_spec.rb` for the established pattern) — the header is the same on
every response.

### Test

`RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/content_security_policy_spec.rb`
— must fail before the initializer change (write it first), pass after. Then
`bundle exec brakeman -q` (CSP file changed; must stay clean).

Commit: `Allow blob: previews and the garage endpoint in CSP`

---

## Task 2 — Center all popup modals

**Bug:** the Add-image dialog (`_add_image_dialog.html.erb:14`, opened via `.showModal()` by
image_upload_controller.js:49) renders **top-left**, not centered. It is the only card modal
excluded from the shared modal CSS (application.css:461 matches `dialog[data-dialog-target="dialog"]`;
this one uses `data-image-upload-target="dialog"`), and the only one without a `max-h` cap.

**In scope:** Add-image, Flag (`_flag_dialog.html.erb:73`), Edit-profile (`_profile_edit.html.erb:75`
— the good reference: `max-h-[90dvh] overflow-hidden open:flex open:flex-col`). The Challenge
dialog (`_challenge_dialog.html.erb:93`) is dead/orphaned but carries `data-dialog-target` — it
inherits the fix for free; do not otherwise touch it.
**Out of scope — must NOT be re-centered:** the full-screen lightbox (lightbox_controller) and
every anchored dropdown (`ui/_menu`, share menu, card menu, hovercard).

### Step 1 — root-cause empirically (systematic-debugging; do this BEFORE writing the fix)

1. `bin/dev`, log in, open the composer, click the image button. Confirm the top-left render.
2. In devtools, inspect the open `<dialog>`'s **computed** `margin` and `position`:
   - `margin: 0px` → a global reset is overriding the UA `margin: auto` (prime suspect:
     Tailwind v4 preflight's universal `margin: 0`; check the preflight block in
     `app/assets/builds/tailwind.css` — and then explain why the OTHER dialogs still center,
     e.g. a rule that covers `[data-dialog-target]` only).
   - `margin: auto` but still top-left → walk the ancestor chain (the dialog sits inside the
     composer form subtree) for `transform`/`filter`/`contain`/`will-change` establishing a
     containing block that captures the top layer.
3. Also open the Flag and Edit-profile dialogs and note whether they center. Record the finding
   in the CSS comment you write in Step 2 — that comment is the deliverable of this step.

### Step 2 — the robust fix (`app/assets/tailwind/application.css`, modal block at ~451)

Regardless of which cause Step 1 found, ship a rule that makes centering **not depend on the
inherited UA `margin: auto`** and fold the Add-image dialog into the shared modal styling:

1. **Widen all six shared-modal selectors** (lines 461, 470, 475, 480, 487, 491) from
   `dialog[data-dialog-target="dialog"]` to
   `dialog[data-dialog-target="dialog"], dialog[data-image-upload-target="dialog"]` — the
   Add-image dialog gains the same entrance/exit animation as every other modal.
   Update the comment at line 451–460 (it currently lists "flag, challenge, profile-edit").
2. **Add an explicit centering rule** next to that block, with a comment recording the Step 1
   finding:

```css
/* Centering for card modals. <Step 1 finding here — e.g. "Tailwind v4 preflight
   resets margin:0 on every element, killing the UA's dialog margin:auto">. This
   rule restates the centered top-layer geometry explicitly so no reset or
   ancestor quirk can break it. Lightbox and dropdowns are not matched — they
   position themselves. */
dialog[data-dialog-target="dialog"],
dialog[data-image-upload-target="dialog"] {
  position: fixed;
  inset: 0;
  margin: auto;
}
```

   Exception: if Step 1 proves the cause is an ancestor `transform`/`will-change` capturing the
   top layer (rare, browser-bug territory), ALSO remove that property from the offending
   ancestor and say so in the comment. The CSS rule above still ships either way.
3. **Height cap** — `_add_image_dialog.html.erb:17`: add `max-h-[90dvh] overflow-y-auto` to the
   class list (same cap as edit-profile; simple scroll rather than the flex-column treatment —
   this dialog has no sticky footer). `max-h-[90dvh]` already compiles (profile_edit uses it).

### Verify

- `bin/dev`: Add-image, Flag, and Edit-profile dialogs all open **centered**, animate in/out,
  and close on Esc/backdrop. Shrink the window height below the dialog: content scrolls inside
  the Add-image dialog instead of overflowing.
- Lightbox still fills the screen; card menu / share menu / hovercard still anchor to their
  triggers (confirm by eye).
- Regression guard: append this assertion to the existing image-upload system spec (find it via
  `grep -rl "Add an image" spec/system`), after the dialog is opened:

```ruby
centered = page.evaluate_script(<<~JS)
  (() => {
    const d = document.querySelector('dialog[data-image-upload-target="dialog"]')
    const r = d.getBoundingClientRect()
    return Math.abs((r.left + r.width / 2) - window.innerWidth / 2) < 4
  })()
JS
expect(centered).to be(true)
```

- Run: `bin/ci --only-system-specs` (rebuilds Tailwind first, which this task requires).

Commit: `Center card modals with explicit top-layer geometry`

---

## Task 3 — Hover/press motion on interactable components

Restrained, consistent pass. Press feedback (`active:scale-95`) mostly exists; hover feedback is
absent and every `transition` is bare (default 150ms, default curve). Treatment: **the button
family gets a real eased transition + a subtle hover lift; state-flip surfaces (filter tabs,
toolbar, menu rows) get an eased transition so their existing flips stop snapping.** Everything
animates transform/opacity/color/background/box-shadow only. No new tokens: `duration-150`/
`duration-200` + the `ease-out` utility.

**Pre-flight check (one minute, do first):** the app's `--ease-out` lives on the unlayered
`:root`, which overrides Tailwind's `@layer theme` value — so the stock `ease-out` utility
should resolve to the house curve at runtime. Confirm:
`bin/rails tailwindcss:build && grep -o '\.ease-out{[^}]*}' app/assets/builds/tailwind.css` —
expect `transition-timing-function: var(--ease-out)`. If (and only if) it inlines a literal
`cubic-bezier(0, 0, 0.2, 1)` instead, substitute `ease-(--ease-out)` for every `ease-out`
prescribed below.

### 3a. `app/helpers/design_system_helper.rb` — the button family

**BASE (lines 31–32):**

```ruby
BASE = "inline-flex items-center justify-center gap-1 no-underline cursor-pointer select-none " \
       "transition duration-150 ease-out active:scale-95 disabled:opacity-50 disabled:cursor-default".freeze
```

**`ds_button_variant` (line 319):** append hover effects per variant — colour-independent, so no
safelist impact (and v4's `scale`/`translate` are separate properties, so the press scale and
hover lift compose):

- `:solid` → append ` hover:-translate-y-0.5 hover:shadow-md`
- `:rect` → append ` hover:-translate-y-0.5`
- `:on_primary` / `:on_primary_outline` → append ` hover:-translate-y-0.5`
- `:link` → append ` hover:opacity-70`
- `else` (the house pill) → append ` hover:-translate-y-0.5 hover:shadow-md`

(Deliberate, documented trade-off: `<a>`-rendered buttons can't use `enabled:`, so a disabled
`<button>` still lifts on hover — it also already shows `cursor-default` + `opacity-50`, which
reads as disabled. Add a one-line comment saying so.)

This automatically covers **Jump in** (`_hujah_card.html.erb:109`, uses `ds_button_classes`) and
every other helper-driven button.

**Menu rows — MENU_ITEM_BASE (line 227):** prepend the transition so `hover:bg-gray-100` eases:

```ruby
MENU_ITEM_BASE = "block w-full text-left px-3 py-3 sm:py-1 text-sm rounded no-underline transition-colors duration-150 ease-out".freeze
```

(The tone spec at design_system_helper_spec.rb:501-505 derives its expectation from the
constants, so it stays green automatically.)

**Spec update:** `spec/helpers/design_system_helper_spec.rb` ~lines 174–186 asserts BASE's token
set — add `duration-150` and `ease-out` to the expected list and keep the surrounding comment
accurate (`active:scale-95` is still the only *press* feedback; hover now lives per-variant).

### 3b. Response-filter tabs — `app/views/hujahs/_response_filter.html.erb` lines 43, 52, 62, 72

Append to each of the four buttons' class strings (they currently have NO transition, so the
`aria-pressed` fill/ring flip snaps): ` transition duration-200 ease-out active:scale-95`.
The default `transition` property set covers background-color and box-shadow (ring), so the
stance fills ease with zero extra classes — do NOT add any `aria-pressed:`/stance hover classes.
Leave the frozen `data-*` contract untouched.

### 3c. Format toolbar B/I/U — `app/views/hujahs/_compose_form.html.erb` lines 87, 91, 95

Each currently: `w-8 h-8 rounded-lg flex items-center justify-center text-ink-2 bg-card-2 active:scale-95`.
Append: ` transition duration-150 ease-out hover:text-ink hover:bg-field` — the scale now eases
and hover gives a soft tint. These act on click only; the textarea keystroke path is untouched
(do not add motion to the textarea, counters, or anything that updates per keystroke).

### 3d. The hand-written Post pill — `_compose_form.html.erb` line 46

It has `transition active:scale-95` inline. Change `transition` to
`transition duration-150 ease-out hover:-translate-y-0.5 hover:shadow-md` so it matches the
helper-driven family. Nothing else on that line changes.

### Test

- `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/helpers/design_system_helper_spec.rb`
- `bin/dev`, by eye: pill buttons and Jump in lift ~2px with a soft shadow on hover and ease
  back; filter tabs cross-fade their stance fill; B/I/U tint on hover and ease their press
  scale; menu rows fade their hover fill. With macOS "Reduce Motion" on, everything is
  effectively instant (global guard — nothing to add).
- `bin/ci --skip-system-specs` (helper + view specs), then rely on the final integration
  `bin/ci` for system specs.

Commit: `Add eased hover and press motion to the button family`

---

## Task 4 — Per-hujah visibility icon

`Hujah` has `enum :visibility, {visible_public: 0, followers_only: 1, private_only: 2},
prefix: :visibility` (hujah.rb:88 — predicates are `visibility_followers_only?` etc.). Replies
inherit the parent's visibility, so the badge appears **only on top-level claims**
(`hujah.parent_id.nil?`).

**Decision: badge non-public posts only** (followers_only → `users`, private_only → `lock`; no
globe). Justification: public is the default state of the entire feed — an icon must mean
"restricted", or it is noise on every card.

### 4a. `app/helpers/icons_helper.rb`

Add (mind this file's house style — `stance_icon` raises on unknowns, but here `nil` for public
is the *designed* answer, not an error; say so in a comment):

```ruby
# Per-post visibility badge, top-level claims only (replies inherit the parent's
# visibility, so callers guard on parent_id.nil?). visible_public maps to NOTHING
# by design: public is the default state of the feed, so an icon here always
# means "restricted". nil-for-public is the contract, not a lapse — unlike
# stance_icon above, where nil input is a caller bug.
VISIBILITY_ICON = {"followers_only" => "users", "private_only" => "lock"}.freeze

def visibility_icon(hujah, **opts)
  name = VISIBILITY_ICON[hujah.visibility]
  lucide_icon(name, **opts) if name
end

def visibility_title(hujah)
  case hujah.visibility
  when "followers_only" then "Only people following @#{hujah.user.username} can see this"
  when "private_only" then "Only @#{hujah.user.username} can see this"
  end
end
```

### 4b. `app/views/hujahs/_hujah_header.html.erb` (feed + single-hujah byline, lines 64–70)

Inside the `<small class="text-xs text-ink-2">`, immediately after the `<time>` element:

```erb
<% if hujah.parent_id.nil? && !hujah.visibility_visible_public? %>
  <span class="mx-1">·</span>
  <span title="<%= visibility_title(hujah) %>"><%= visibility_icon(hujah, class: "w-3.5 h-3.5 text-ink-2 inline") %></span>
<% end %>
```

### 4c. `app/views/users/_user_hujah.html.erb` (profile compact card, byline at lines 42–47)

After the closing `<% end %>` of the name/username `ui/user_link` (line 46), still inside the
byline `<div>`. This card overlays an inset link anchor (`absolute inset-0 z-0`), so the badge
needs `relative z-10` for its native `title` tooltip to receive hover:

```erb
<% if hujah.parent_id.nil? && !hujah.visibility_visible_public? %>
  <span class="relative z-10" title="<%= visibility_title(hujah) %>"><%= visibility_icon(hujah, class: "w-3.5 h-3.5 text-ink-2 inline") %></span>
<% end %>
```

All classes are ERB literals already emitted elsewhere — no safelist changes.

### Specs

- Extend `spec/helpers/icons_helper_spec.rb`: `visibility_icon` returns nil for a
  `visible_public` hujah, renders `users` for `followers_only` and `lock` for `private_only`
  (build via `build(:hujah, visibility: :followers_only)`); `visibility_title` returns the two
  exact strings and nil for public.
- Extend `spec/views/users/_user_hujah_spec.rb` (follow its existing render/locals pattern): a
  top-level `followers_only` hujah renders an element whose `title` includes "can see this"; a
  `visible_public` one renders none.

### Test

`RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/helpers/icons_helper_spec.rb spec/views/users/_user_hujah_spec.rb`,
then eyeball a followers-only and a private post in `bin/dev` (feed, single-hujah, profile).

Commit: `Show a visibility icon on restricted top-level hoojahs`

---

## Final integration (serial, after all four tasks)

1. `bundle exec standardrb` — fix anything it flags.
2. `bin/ci` — the definition of green (gates + full suite; one run at a time on the shared
   test DB).
3. Spot-check in `bin/dev`: upload an image end-to-end (dev uses local storage, so the CSP fix
   is only fully provable in production — the request spec is the guard), open all three
   dialogs, hover the button family, view a followers-only post.
