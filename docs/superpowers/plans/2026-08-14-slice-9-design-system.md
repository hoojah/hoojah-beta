# Slice 9: Design System Adoption + Debate Structured Phases — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Adopt the Hoojah Design System across all ~75 views, and give debate turns named
Opening / Counter / Response / Closing phases derived from a 4-round default.

**Architecture:** Tokens land in Tailwind v4 `@theme` + a `:root` block; four ERB primitives
(`ui/_card`, `ui/_divider`, `ui/_empty_state`, `ui/_avatar`) plus a `DesignSystemHelper` replace
copy-pasted markup; views are refactored family by family. Debate phase is a **pure derivation**
from turn position and a new `debates.rounds_limit` column — no column on `debate_turns`.

**Tech Stack:** Rails 8.1.3.1 / Ruby 3.4.9, Hotwire (Turbo + Stimulus), Tailwind CSS v4
(`tailwindcss-rails`), `lucide-rails`, Pundit, RSpec + Cuprite.

**Source spec:** `docs/superpowers/specs/2026-08-14-design-system-and-debate-phases-design.md` — READ IT.
**Design reference:** `docs/design-system/` (mirror). Start at `readme.md`, then `MIRROR-NOTES.md`.

## Canonical commands (HANDOVER.md)
- Rails: `mise exec ruby@3.4.9 -- bin/rails <args>`
- Specs: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>`
  (iterate fast with `--exclude-pattern "spec/system/**/*"`)
- `bin/rails db:test:prepare` after migrations (NOT `db:prepare` — it seeds and pollutes count assertions)
- Gates each task: full suite green, `standardrb`, brakeman **0**, `bundler-audit` clean

Branch `slice-9-design-system` (already created; spec + mirror committed at `3e2cd3d`).
Commit per task, **no attribution trailer** (workspace rule).
Baseline **273 examples / 0 failures / 2 pending**; system dir 24 examples.

> HANDOVER.md says 271 — that entry was written at `1471474`, and `11be59a` ("harden timeout job +
> verdict-visibility request spec") added two more before the merge. `rspec --dry-run` on `master`
> is the authority: **273**. Fix the stale number in HANDOVER during Task 5.1.

## THE FREEZE RULE (applies to every task in Phase 4)

Markup and CSS classes may change. These may **not**:

- any `dom_id(...)` — Slice 8 broadcasts target `dom_id(debate, :transcript|:composer|:status|:actions)`
  and `dom_id(hujah, :vote_bars|:debates)`, `dom_id(user, :profile_header)`, `dom_id(notification)`
- any `data-*` attribute — `data-controller`, `data-action`, `*-target`, and specifically
  `data-response-filter-target` / `data-response-filter-vote`, `data-testid`
- form actions, HTTP verbs, `button_to`/`form_with` URLs, strong-param field names
- rendered user-visible copy
- the `viewer:` local contract on `debates/_debate_actions` and `debates/_turn_composer`
  (`local_assigns.fetch(:viewer) { current_user }`) — `current_user` is undefined in a broadcast render

Breaking any of these breaks real-time or filtering **silently**. The Cuprite specs are the guard.

---

# Phase 1 — Token foundation + brand assets (spec Parts A + B)

### Task 1.1: Port the 72 tokens into `@theme` + `:root`
**Files:** modify `app/assets/tailwind/application.css`. Test: `spec/system/design_tokens_spec.rb` (create).

Tailwind v4 only generates utilities for **namespaced** variables. Split accordingly:
`@theme` gets `--color-*`, `--text-*` (+ `--text-*--line-height`), `--font-weight-*`, `--tracking-*`,
`--leading-*`, `--radius-*`, `--shadow-*`. Everything else (semantic aliases, fixed pixel sizes) is a
plain custom property in `:root` — consumed via `var()`, not via a utility class.

- [ ] **Step 1: Extend `@theme`** — keep the existing 7 colors, add:

```css
@theme {
  /* existing 7 kept verbatim: primary agree neutral disagree black grey light-grey */
  --color-white: #ffffff;
  --color-gray-50: #f9fafb;
  --color-gray-100: #f3f4f6;
  --color-gray-200: #e5e7eb;
  --color-red-50: #fef2f2;
  --color-red-700: #b91c1c;
  /* THE LATENT GAP: border-read / border-unread are used by
     app/views/notifications/_notification_card.html.erb and defined nowhere. */
  --color-unread: #e1306c;      /* stance neutral pink, matching the unread dot */
  --color-read: #bac2ca;        /* light-grey */

  --text-xs: 12px;   --text-xs--line-height: 16px;
  --text-sm: 14px;   --text-sm--line-height: 20px;
  --text-base: 16px; --text-base--line-height: 24px;
  --text-lg: 18px;   --text-lg--line-height: 1.375;
  --text-xl: 20px;   --text-xl--line-height: 1.375;
  --text-2xl: 24px;  --text-2xl--line-height: 32px;

  --font-weight-medium: 500;
  --font-weight-semibold: 600;
  --font-weight-bold: 700;
  --leading-snug: 1.375;
  --tracking-wide: 0.025em;

  --radius-none: 0;
  --radius: 4px;
  --radius-lg: 8px;
  --radius-full: 9999px;

  --shadow-sm: 0 1px 2px 0 rgb(0 0 0/0.05);
  --shadow: 0 1px 3px 0 rgb(0 0 0/0.1), 0 1px 2px -1px rgb(0 0 0/0.1);
  --shadow-lg: 0 10px 15px -3px rgb(0 0 0/0.1), 0 4px 6px -4px rgb(0 0 0/0.1);
}
```

  Do **not** redefine `--spacing`: the DS `--space-1..6` are the 4px Tailwind steps the default
  theme already provides.

- [ ] **Step 2: Add the `:root` block** (semantic aliases + fixed sizes, `var()`-only):

```css
:root {
  --surface-page: #ffffff;  --surface-card: #ffffff;  --surface-menu: #ffffff;
  --surface-nav: rgba(255,255,255,0.9);  --surface-profile: var(--color-primary);
  --text-body: var(--color-black);  --text-muted: var(--color-grey);
  --text-faint: var(--color-light-grey);  --text-link: var(--color-primary);
  --text-inverse: var(--color-white);
  --border-hairline: var(--color-gray-100);  --border-field: var(--color-gray-200);
  --track-bar: var(--color-gray-200);  --backdrop: rgba(0,0,0,0.4);
  --border-stance: 8px;  --border-pill: 2px;
  --nav-h: 56px;  --content-max: 576px;  --sidebar-w: 256px;
  --vote-btn: 44px;  --bar-h: 8px;
  --avatar-lg: 96px; --avatar-md: 44px; --avatar-row: 40px; --avatar-nav: 36px; --avatar-sm: 32px;
}
```

- [ ] **Step 3: Extend the safelist** — `_notification_card` interpolates `border-<read|unread>`
  exactly as the vote widget interpolates stance classes, so Tailwind's scanner cannot see them:

```css
@source inline("{bg,text,border,fill}-{agree,neutral,disagree,primary}");
@source inline("border-{read,unread}");
@source inline("fill-white text-white bg-white");
```

- [ ] **Step 4: Add the base layer** (port of `docs/design-system/tokens/base.css`). This is what
  finally gives `<body class="body">` in `app/views/layouts/application.html.erb` meaning — `.body`
  is currently defined **nowhere** in the app:

```css
@layer base {
  body { font-family: var(--font-sans); color: var(--text-body); background: var(--surface-page); margin: 0; }
  a { color: var(--text-link); text-decoration: none; }
  a:hover { color: var(--text-link); }
}
```

- [ ] **Step 5: Build** — `mise exec ruby@3.4.9 -- bin/rails tailwindcss:build`.
  Expected: exits 0. Then assert the gap is closed:
  `grep -c "border-unread\|border-read" app/assets/builds/tailwind.css` → **≥ 2**.
  If 0, the `@source inline` in Step 3 is wrong — fix before continuing.
- [ ] **Step 6: Failing → passing system spec** — `spec/system/design_tokens_spec.rb`: visit
  `/notifications` as a signed-in user with one unread + one read notification (reuse
  `login_as_system`); assert both cards render and their computed `border-left-color` is
  `rgb(225, 48, 108)` (unread) and `rgb(186, 194, 202)` (read) via
  `page.evaluate_script("getComputedStyle(document.querySelector('#<dom_id>')).borderLeftColor")`.
  Run before Step 1 conceptually — here, confirm it FAILS on `master`'s CSS and PASSES now.
- [ ] **Step 7: Full suite + `standardrb`. Commit.**

### Task 1.2: Vendor and repair the brand assets
**Files:** create `app/assets/images/logo.svg`; modify `app/views/shared/_navbar.html.erb`.
Test: `spec/system/branding_spec.rb` (create).

- [ ] **Step 1: Copy + repair the logo.** `docs/design-system/assets/logo.svg` renders **solid
  black**: its paths carry `class="st0"`…`class="st6"`, the file has no `<style>` block, and its
  seven `radialGradient` defs are never referenced. (The DS `readme.md` claims these fills were
  restored — they were not; see `docs/design-system/MIRROR-NOTES.md` §1.) Copy to
  `app/assets/images/logo.svg` and add a `fill` to each path/line on the sibling mapping:

  | class | element id | add |
  | --- | --- | --- |
  | `st0` | `XMLID_13_` | `fill="url(#XMLID_18_)"` |
  | `st1` | `XMLID_169_` | `fill="url(#XMLID_148_)"` |
  | `st2` | `XMLID_175_` | `fill="url(#XMLID_149_)"` |
  | `st3` | `XMLID_7_` | `fill="url(#XMLID_150_)"` |
  | `st4` | `XMLID_8_` | `stroke="url(#XMLID_151_)"` (it is a `<line>`, not a path) |
  | `st5` | `XMLID_11_` | `fill="url(#XMLID_152_)"` |
  | `st6` | `XMLID_15_` | `fill="url(#XMLID_153_)"` |

- [ ] **Step 2: Swap the navbar wordmark.** In `shared/_navbar.html.erb` replace the text brand
  with the asset, keeping the link target and the accessible name:

```erb
<%= link_to root_path, class: "flex items-center no-underline", aria: { label: "Hoojah" } do %>
  <%= image_tag "logo.svg", alt: "Hoojah", class: "h-7 w-auto" %>
<% end %>
```

- [ ] **Step 3: Spec** — `spec/system/branding_spec.rb`: visiting `/` renders `img[alt="Hoojah"]`
  whose `src` matches `/logo`, and the link points at `root_path`.
- [ ] **Step 4: Run → PASS. Full suite. Commit.**

**Do NOT wire `pinned-tab.svg`** — it is a degenerate potrace output (a filled black rectangle over
the whole viewBox) and would render a black square in Safari's tab strip.
**Do NOT present `loading.svg` as a spinner** — its `<animate>` children were stripped upstream, so
it is static. Neither is vendored this slice.

---

# Phase 2 — ERB primitives (spec Part C)

### Task 2.1: `DesignSystemHelper#ds_button_classes` + `STANCE_COLOR`
**Files:** create `app/helpers/design_system_helper.rb`; modify `app/helpers/icons_helper.rb`.
Test: `spec/helpers/design_system_helper_spec.rb` (create).

- [ ] **Step 1: Failing spec** — every variant returns the DS shape:
  `outline` → contains `rounded-full`, `border-2`, `border-primary`, `text-primary`, `bg-white`,
  `shadow`, `active:scale-95`; `tone: "agree"` swaps `primary`→`agree` in border+text;
  `solid` → `bg-primary text-white`, no `border-2`; `rect` → `rounded` not `rounded-full`;
  `on_primary` → `bg-white text-primary`; `link` → no border, no shadow, no padding;
  `size: :sm` → `px-4 py-1 text-sm`, default → `px-5 py-2`;
  an unknown variant falls back to `outline`; an unknown tone falls back to `primary`.
- [ ] **Step 2: Run → FAIL** (`uninitialized constant DesignSystemHelper`).
- [ ] **Step 3: Implement.**

```ruby
module DesignSystemHelper
  TONES = %w[primary agree neutral disagree grey light-grey].freeze
  BASE = "inline-flex items-center justify-center gap-1 no-underline cursor-pointer transition active:scale-95".freeze

  def ds_button_classes(variant: :outline, tone: "primary", size: :md)
    tone = TONES.include?(tone.to_s) ? tone.to_s : "primary"
    pad = (size.to_sym == :sm) ? "px-4 py-1 text-sm" : "px-5 py-2"
    [BASE, ds_button_variant(variant.to_sym, tone, pad)].join(" ")
  end

  private

  def ds_button_variant(variant, tone, pad)
    case variant
    when :solid then "#{pad} rounded-full bg-#{tone} text-white fill-white shadow"
    when :rect then "#{pad} rounded bg-#{tone} text-white fill-white"
    when :on_primary then "px-4 py-1 text-sm rounded-full bg-white text-primary fill-primary"
    when :on_primary_outline then "px-4 py-1 text-sm rounded-full border border-white text-white fill-white bg-transparent"
    when :link then "border-0 bg-transparent p-0 text-#{tone} fill-#{tone}"
    else "#{pad} rounded-full border-2 border-#{tone} text-#{tone} fill-#{tone} bg-white shadow"
    end
  end
end
```

  Then add to `IconsHelper` alongside the existing `STANCE_ICON`:

```ruby
  STANCE_COLOR = {"agree" => "agree", "neutral" => "neutral", "disagree" => "disagree"}.freeze

  def stance_color(stance) = STANCE_COLOR.fetch(stance.to_s, "primary")
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Safelist the new tones** — `ds_button_classes` interpolates `bg-#{tone}` /
  `border-#{tone}` / `text-#{tone}` / `fill-#{tone}`, including `grey` and `light-grey` which the
  existing `@source inline` does not cover. Extend it in `app/assets/tailwind/application.css`:
  `@source inline("{bg,text,border,fill}-{grey,light-grey}");` then rebuild and grep to confirm.
- [ ] **Step 6: Full suite + `standardrb`. Commit.**

### Task 2.2: `ui/_avatar` with the initials fallback
**Files:** create `app/views/ui/_avatar.html.erb`; modify `app/helpers/design_system_helper.rb`.
Test: `spec/helpers/design_system_helper_spec.rb`, `spec/views/ui/avatar_spec.rb` (create).

`image_tag user.photo` with a blank photo raises today — this partial is the fix, not just a restyle.

- [ ] **Step 1: Failing spec** — `ds_initials("Maya Zaharudin")` → `"MZ"`; `ds_initials("Maya")` →
  `"M"`; `ds_initials("")` and `ds_initials(nil)` → `"?"`; three-or-more words take the first two.
  View spec: rendering with `photo: nil` produces **no `<img>`** and shows the initials with
  `aria-label` set to the user's name; with a photo present it produces an `<img>` with that `src`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement.** Helper:

```ruby
  def ds_initials(name)
    parts = name.to_s.strip.split(/\s+/).first(2)
    return "?" if parts.empty?
    parts.filter_map { |w| w[0] }.join.upcase
  end
```

  `app/views/ui/_avatar.html.erb` (locals: `user`, `size:` one of `lg md row nav sm`):

```erb
<% px = {lg: "w-24 h-24", md: "w-11 h-11", row: "w-10 h-10", nav: "w-9 h-9", sm: "w-8 h-8"}
     .fetch(local_assigns.fetch(:size, :md).to_sym) %>
<% if user.photo.present? %>
  <%= image_tag user.photo, alt: user.username,
        class: "rounded-full object-cover shrink-0 #{px} #{local_assigns[:class]}" %>
<% else %>
  <span aria-label="<%= user.full_name %>"
        class="rounded-full shrink-0 inline-flex items-center justify-center bg-primary text-white font-medium #{px} #{local_assigns[:class]}">
    <%= ds_initials(user.full_name) %>
  </span>
<% end %>
```

- [ ] **Step 4: Run → PASS. Full suite. Commit.**

### Task 2.3: `ui/_card`, `ui/_divider`, `ui/_empty_state`
**Files:** create `app/views/ui/_card.html.erb`, `_divider.html.erb`, `_empty_state.html.erb`.
Test: `spec/views/ui/card_spec.rb`, `spec/views/ui/empty_state_spec.rb` (create).

- [ ] **Step 1: Failing specs** — card renders `shadow bg-white` and **no** rounding class;
  with `stance: "agree"` it adds `border-l-8 border-agree`; `as: "article"` emits `<article>`;
  `id:` passes through. Empty state renders a Lucide `<svg>` and the given sentence with
  `text-light-grey`; `tone: :muted` uses `text-grey`; `icon: nil` renders no `<svg>`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement.**

`_card` wraps a block, so it is a **layout partial**. The three call forms, **verified empirically
during Task 2.3** (this section previously claimed otherwise and was wrong in both directions):

| Call | Behaviour |
| --- | --- |
| `render layout: "ui/card" do … end` | **works** — `yield` receives the block. The canonical form. |
| `render "ui/card" do … end` | **also works.** A bare string with a block takes the `else` branch and forwards the block to `render_partial`. My earlier claim that this "silently drops the block" was false. |
| `render partial: "ui/card" do … end` | **raises loudly** — `ArgumentError: 'nil' is not an ActiveModel-compatible object`. Given a Hash *and* a block, `RenderingHelper#render` renders `options[:layout]` and ignores `options[:partial]`, so it looks up nil. |

So the footgun is real but **not silent**, which is what matters for Phase 4: no agent can ship an
empty card this way. Both behaviours are pinned in `spec/views/ui/card_spec.rb`.

```erb
<%# app/views/ui/_card.html.erb — LAYOUT partial. locals: as:, stance:, padded:, id:, class: %>
<% tag_name = local_assigns.fetch(:as, "div")
   stance = local_assigns[:stance]
   classes = ["shadow bg-white",
              ("border-l-8 border-#{stance}" if stance.present?),
              ("px-4 py-3" if local_assigns[:padded]),
              local_assigns[:class]].compact.join(" ") %>
<%= content_tag tag_name, id: local_assigns[:id], class: classes do %><%= yield %><% end %>
```

Call site shape (this exact form is what Phase 4 must use):

```erb
<%= render layout: "ui/card", locals: {as: "article", id: dom_id(hujah), class: "mb-2"} do %>
  …card contents…
<% end %>
```

```erb
<%# app/views/ui/_divider.html.erb %>
<div class="border-t border-gray-100 <%= local_assigns[:class] %>"></div>
```

```erb
<%# app/views/ui/_empty_state.html.erb — locals: message, icon:, tone:, align: %>
<% tone = (local_assigns.fetch(:tone, :faint).to_sym == :muted) ? "text-grey fill-grey" : "text-light-grey fill-light-grey" %>
<% align = (local_assigns.fetch(:align, :left).to_sym == :center) ? "justify-center" : "justify-start" %>
<div class="flex items-center gap-1 text-sm p-3 bg-white <%= tone %> <%= align %>">
  <% icon = local_assigns.fetch(:icon, "message-circle") %>
  <%= lucide_icon(icon, class: "w-4 h-4") if icon.present? %>
  <span><%= message %></span>
</div>
```

- [ ] **Step 4: Run → PASS. Full suite + `standardrb`. Commit.**

---

# Phase 3 — Debate structured phases (spec Part E)

Independent of Phases 1–2; can run in parallel.

### Task 3.1: `rounds_limit` migration with the safe backfill
**Files:** create `db/migrate/<ts>_add_rounds_limit_to_debates.rb`. Test: `spec/models/debate_phase_spec.rb` (create).

A blanket `default: 4` would put already-long **active** debates past their cap and auto-conclude
them on their next turn. Backfill actives to `current_round + 1` instead.

- [ ] **Step 1: Migration.**

```ruby
class AddRoundsLimitToDebates < ActiveRecord::Migration[8.1]
  def up
    add_column :debates, :rounds_limit, :integer, null: false, default: 4
    # current_round == turns.count / 2 + 1, so current_round + 1 == count / 2 + 2.
    # status 1 == :active — an integer literal so this migration never couples to the enum.
    execute <<~SQL
      UPDATE debates SET rounds_limit = GREATEST(
        4,
        (SELECT COUNT(*) FROM debate_turns WHERE debate_turns.debate_id = debates.id) / 2 + 2
      ) WHERE status = 1
    SQL
  end

  def down
    remove_column :debates, :rounds_limit
  end
end
```

- [ ] **Step 2:** `mise exec ruby@3.4.9 -- bin/rails db:migrate` then `bin/rails db:test:prepare`.
- [ ] **Step 3: Spec** — an `active` debate with 10 turns backfills to `7` (10/2+2), a
  `concluded` debate with 10 turns stays `4`, a fresh debate is `4`.
- [ ] **Step 4: Run → PASS. Commit.**

### Task 3.2: Phase derivation + turn cap + `extend_rounds!`
**Files:** modify `app/models/debate.rb`, `app/models/debate_turn.rb`.
Test: `spec/models/debate_phase_spec.rb`.

- [ ] **Step 1: Failing specs.**
  - `DebateTurn#round`: positions 1,2→1; 3,4→2; 5,6→3; 7,8→4
  - `phase_for` at `rounds_limit: 4` → 1 `:opening`, 2 `:counter`, 3 `:response`, 4 `:closing`;
    at `rounds_limit: 5` → 4 becomes `:counter`, 5 `:closing`
  - posting the 8th turn at `rounds_limit: 4` concludes the debate
  - the capping turn creates **no** `debate_your_turn` notification (assert the count of that
    category is unchanged), while turns 1–7 each create exactly one
  - `conclude!(by: nil)` still notifies both participants and awards `first_debate`
  - `extend_rounds!` guard matrix: non-participant → false; non-active → false; before the closing
    round (`turns.count < (rounds_limit-1)*2`) → false; at the ceiling (`rounds_limit == 10`) → false;
    **with a turn already in the closing round → false**, and — the reason that guard exists —
    assert the already-posted turn's `phase` is still `:closing` afterwards
  - a successful `extend_rounds!` bumps `rounds_limit` by 1 and the cap moves accordingly
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement.** `app/models/debate.rb`:

```ruby
  PHASE_LABELS = {opening: "Opening statement", counter: "Counter-argument",
                  response: "Response", closing: "Closing statement"}.freeze
  MAX_ROUNDS = 10

  # Pure derivation — nothing is stored on debate_turns.
  def phase_for(round)
    return :opening if round == 1
    return :closing if round == rounds_limit
    round.even? ? :counter : :response
  end

  def final_position = rounds_limit * 2

  # Only at the closing-round BOUNDARY: the round has been reached but holds no turn yet.
  # Extending once a closing turn exists would silently relabel it from CLOSING to COUNTER,
  # because phase is derived at render time.
  def extendable_by?(user)
    active? && participant?(user) && rounds_limit < MAX_ROUNDS &&
      turns.count == (rounds_limit - 1) * 2
  end

  def extend_rounds!(by:)
    return false unless extendable_by?(by)
    update!(rounds_limit: rounds_limit + 1)
    broadcast_state_change
    true
  end
```

  Replace `post_turn`'s notify/broadcast tail (everything after the `with_lock` block):

```ruby
    capped = turn.position >= final_position
    notify(other(by), :debate_your_turn) unless capped
    broadcast_append_later_to self, target: dom_id(self, :transcript),
      partial: "debates/debate_turn", locals: {debate_turn: turn}
    broadcast_to_each_participant(target: :composer, partial: "debates/turn_composer")
    conclude!(by: nil) if capped
    true
```

  `app/models/debate_turn.rb`:

```ruby
  def round = ((position - 1) / 2) + 1

  def phase = debate.phase_for(round)

  def phase_label = Debate::PHASE_LABELS.fetch(phase)
```

- [ ] **Step 4: Run → PASS. Full suite (the Slice 4/8 debate specs must stay green). Commit.**

### Task 3.3: Extend endpoint — policy, route, throttle, controller
**Files:** modify `app/policies/debate_policy.rb`, `config/routes.rb`,
`config/initializers/rack_attack.rb`, `app/controllers/debates_controller.rb`;
create `app/views/debates/extend_rounds.turbo_stream.erb`.
Test: `spec/policies/debate_policy_spec.rb`, `spec/requests/debate_extend_spec.rb` (create).

- [ ] **Step 1: Failing specs** — participant on an active debate at the boundary → 302/turbo_stream
  and `rounds_limit` +1; non-participant → **403**; participant mid-closing-round → 422 with
  `rounds_limit` unchanged; at the ceiling → 422; anonymous → login redirect.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement.** Policy: `def extend? = record.participant?(user) && record.active?`
  (the finer boundary/ceiling conditions live in `extendable_by?`, so a legitimate participant gets
  a 422 rather than a 403 — authorization and applicability are different answers).
  Route: `post "/debates/:slug/extend", to: "debates#extend_rounds", as: :extend_debate`.
  rack-attack: a `debate_extend/user` throttle at **10/min**, mirroring the existing
  `debate_verdicts/user` block. Controller:

```ruby
  def extend_rounds
    @debate = Debate.friendly.find(params[:slug])
    authorize @debate, :extend?
    if @debate.extend_rounds!(by: current_user)
      respond_to { |f| f.turbo_stream; f.html { redirect_to debate_path(@debate.slug) } }
    else
      head :unprocessable_content
    end
  end
```

  `extend_rounds.turbo_stream.erb` replaces **both** regions — the async broadcast never fires in
  dev (no worker), so the actor's own buttons must update synchronously (the Slice 8 review catch):

```erb
<%= turbo_stream.replace dom_id(@debate, :status) do %>
  <%= render "debates/debate_status", debate: @debate %>
<% end %>
<%= turbo_stream.replace dom_id(@debate, :actions) do %>
  <%= render "debates/debate_actions", debate: @debate, viewer: current_user %>
<% end %>
```

- [ ] **Step 4: Run → PASS. Full suite + brakeman 0. Commit.**

### Task 3.4: Phase labels in the transcript + the Extend affordance
**Files:** modify `app/views/debates/_debate_turn.html.erb`, `_debate_status.html.erb`,
`_debate_actions.html.erb`. Test: `spec/system/debate_phases_spec.rb` (create).

- [ ] **Step 1: Failing system spec** — drive challenge → accept → 8 turns; assert the phase label
  above turn 1 reads "Opening statement", turn 3 "Counter-argument", turn 5 "Response", turn 7
  "Closing statement"; after the 8th turn the debate is concluded and the verdict block appears.
  Second example: at the closing-round boundary a participant clicks "Extend by one round",
  `ROUND 4 OF 5` renders, and the label on turn 7 is now "Counter-argument".
  Reuse `login_as_system` and switch participants mid-flow (Slice 3 harness).
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement.** In `_debate_turn.html.erb`, above the byline — DS micro-label style
  (12px, uppercase, wide tracking), same treatment as the debate state label:

```erb
<div class="text-xs uppercase tracking-wide text-grey mb-1"><%= debate_turn.phase_label %></div>
```

  In `_debate_status.html.erb`, alongside the state label, for an active debate:

```erb
<div class="text-xs uppercase tracking-wide text-grey">
  Round <%= [debate.current_round, debate.rounds_limit].min %> of <%= debate.rounds_limit %>
</div>
```

  In `_debate_actions.html.erb` — note it takes the explicit `viewer:` local, never `current_user`:

```erb
<% if debate.extendable_by?(viewer) %>
  <%= button_to "Extend by one round", extend_debate_path(debate.slug),
        method: :post, class: ds_button_classes(variant: :outline, size: :sm) %>
<% end %>
```

- [ ] **Step 4: Run → PASS. Full suite. Commit.**

---

# Phase 4 — View refactor by DS family (spec Part D)

**Dispatcher note:** each 4.x task is dispatched to a fresh subagent that sees only its own prompt.
The prompt MUST inline **THE FREEZE RULE** and the five steps below verbatim — do not assume the
subagent reads the rest of this file, and do not assume it reads tasks in order.

**Every task below follows the same five steps.** Re-read THE FREEZE RULE first. Per family:

1. Read `docs/design-system/readme.md` (VISUAL FOUNDATIONS + CONTENT FUNDAMENTALS) and that
   family's `docs/design-system/components/<family>/*.prompt.md`.
2. Refactor the listed views to use `ui/_card`, `ui/_divider`, `ui/_empty_state`, `ui/_avatar` and
   `ds_button_classes` in place of hand-written markup; align spacing/type/color to the tokens.
3. `git diff` and verify **no** `dom_id`, `data-*`, form action, strong-param name, `viewer:` local
   or user-visible string changed.
4. Full suite (`standardrb` too) — the 24 Cuprite specs are the real guard.
5. Commit.

### Task 4.1: navigation
**Files:** `app/views/shared/_navbar.html.erb`, `app/views/hujahs/_feed_tabs.html.erb`.
- [ ] Steps 1–5 above. Additionally **fix the dead link**: `_navbar` renders
  `link_to "Your profile", "#"` — point it at `profile_path(current_user.username)`.
  Use `ui/_avatar` (`size: :nav`) for the menu trigger. Keep the `<details>` dropdown (the DS
  documents `<details>` as the menu mechanism) and the 8px `bg-neutral` unread dot — never a count.

### Task 4.2: voting
**Files:** `app/views/hujahs/_vote_bars.html.erb`, `_stance_picker.html.erb`, `_response_filter.html.erb`.
- [ ] Steps 1–5. `_vote_bars` keeps its `dom_id(hujah, :vote_bars)` wrapper and every
  `button_to hujah_votes_path` with `params: {vote: choice}` **unchanged** — it is the Turbo-Stream
  replace target for `votes/create.turbo_stream.erb`. `_response_filter` keeps
  `data-response-filter-target` / `data-response-filter-vote` exactly.

### Task 4.3: hujah
**Files:** `app/views/hujahs/_hujah_card.html.erb`, `_hujah_header.html.erb`, `_child_card.html.erb`,
`_parent_card.html.erb`, `_compose_form.html.erb`, `_share_menu.html.erb`, `_load_more.html.erb`,
`index.html.erb`, `index.turbo_stream.erb`, `show.html.erb`, `new.html.erb`.
- [ ] Steps 1–5. Keep `data-testid="hujah-card"`. `_child_card`'s 8px stance left border is the
  signature motif — route it through `ui/_card`'s `stance:` local. Body type stays 18px
  `leading-snug` in the feed and 20px on `show`. Keep `dom_id(@hujah, :debates)` on the Debates lens.

### Task 4.4: social
**Files:** `app/views/users/*` (10 files), `app/views/notifications/*` (3),
`app/views/trending/*` (2), `app/views/shared/_pinned.html.erb`, `app/views/blocks/*` (3),
`app/views/follows/*` (2).
- [ ] Steps 1–5. `_profile_header` keeps `dom_id(user, :profile_header)` and uses
  `ds_button_classes(variant: :on_primary)` for its white-on-blue controls.
  `_notification_card` keeps `dom_id(notification)` and its interpolated `border-<read|unread>`
  (now backed by real tokens from Task 1.1). `_pinned` colors are fixed by the DS — purple card,
  orange button; do not retint. Replace the six repeated empty states with `ui/_empty_state`.

### Task 4.5: debate
**Files:** `app/views/debates/*` (8), `app/views/debate_turns/create.turbo_stream.erb`,
`app/views/debate_verdicts/create.turbo_stream.erb`.
- [ ] Steps 1–5. **Highest-risk family.** All four pinned `dom_id`s and both `viewer:` locals must
  survive. `_debate_turn` keeps its `dom_id(debate_turn)` wrapper — that id-dedup is what makes the
  synchronous controller response and the async broadcast idempotent. Apply `DEBATE_STATE_COLOR`
  from `components/debate/DebateCard.prompt.md`: pending → agree orange, active → primary,
  concluded → grey, declined → light-grey.

### Task 4.6: forms
**Files:** `app/views/devise/**` (12), `app/views/users/_profile_edit.html.erb`.
- [ ] Steps 1–5. Auth screens use `ds_button_classes(variant: :rect)`; "Save changes" uses `:solid`.
  Error summaries go at the top of the form, not per field (`devise/shared/_error_messages`) — the
  only place red appears in Hoojah.

### Task 4.7: analytics
**Files:** `app/views/analytics/show.html.erb`, `_stat.html.erb`, `_distribution_bar.html.erb`.
- [ ] Steps 1–5. **Keep the k=5 suppression copy and behaviour** ("fewer than 5 votes") — it is a
  privacy floor, not styling. `_distribution_bar` stays a deliberate copy of the bar markup, NOT a
  shared partial with `_vote_bars` (which is welded to a `button_to` vote form).

### Task 4.8: overlays
**Files:** `app/views/hujahs/_flag_dialog.html.erb`, `_challenge_dialog.html.erb`.
- [ ] Steps 1–5. Keep native `<dialog>` + the existing `dialog_controller` and the
  `dom_id(argument, :challenge_dialog)` target. DS shape: `rounded-lg`, `shadow-lg`,
  `backdrop:bg-black/40`, `max-w-md`, hairline header with title + X.

---

# Phase 5 — Gates + docs

### Task 5.1: Full gate sweep + HANDOVER/README update
**Files:** modify `docs/superpowers/HANDOVER.md`, `README.md`.
- [ ] **Step 1: Rebuild CSS** — `bin/rails tailwindcss:build` (the refactor introduces utility
  classes that must be present in the compiled bundle; `app/assets/builds/tailwind.css` is
  gitignored and built by the `assets:precompile` hook).
- [ ] **Step 2: Full suite** — expect **≥ 273 + new examples**, 0 failures, 2 pending. Run the
  system dir **twice** to confirm stability.
- [ ] **Step 2b: Drop the dead `.body` class.** Task 1.1's `@layer base` styles the `body`
  *element*, which is correct. That leaves `class="body"` in `app/views/layouts/application.html.erb`
  matching no rule anywhere — remove the attribute. (Do **not** add a `.body` selector; the element
  selector is the right mechanism.)
- [ ] **Step 3: `standardrb`, `brakeman` (0), `bundler-audit`.**
- [ ] **Step 4: Grep for regressions** —
  `grep -rn "image_tag .*\.photo" app/views` should return **nothing** (all avatars go through
  `ui/_avatar`); `grep -rn 'link_to "Your profile", "#"' app/views` → nothing.
- [ ] **Step 5: Write the HANDOVER section** — Slice 9 summary, the three DS asset defects, the
  `border-read`/`border-unread` fix, the phase model, and the deferrals below. Commit.

## Definition of done
- All 72 tokens available; `border-read`/`border-unread` render real colors; `.body` is defined.
- Gradient wordmark in the navbar; the two broken assets documented and deliberately unwired.
- Four `ui/` primitives + `DesignSystemHelper` exist and are used across all nine view families.
- Debate turns carry derived phase labels; 4-round default; boundary-only extension to 10 rounds max.
- Suite green, brakeman 0, `standardrb` clean, `bundler-audit` clean.

## Deferred
- `pinned-tab.svg` repair + favicon/apple-touch-icon wiring (needs a real monochrome mark).
- `loading.svg` animation restoration.
- `app-icon-512.png` — not mirrored; fetch when Project 3 (Hotwire Native) starts.
- The 40 `*.d.ts`, the non-core `*.jsx`, the 16 `guidelines/*.html` and the 9 `ui_kits/web/*.jsx` —
  fetchable on demand via the `DesignSync` MCP tool (main-loop only; see `MIRROR-NOTES.md`).
- `debate_won` badge (still blocked on a finalized verdict tally, per Slice 8).
- Carried forward from the program: Vote array→scalar, serializer N+1 / prosopite,
  `Api::V1` visibility/block parity, `config.require_master_key` (L4), `rack-cors` (M1),
  Project 3 — Hotwire Native.
