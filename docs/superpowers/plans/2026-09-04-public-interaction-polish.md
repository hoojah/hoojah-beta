# Public & Interaction Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship four polish items — a slower/safer conviction-vote hold, dismissible dropdowns everywhere, an em-dash-free copy pass, and a redesigned set of public static pages.

**Architecture:** Three file-disjoint tracks that can run in parallel. Track A rewrites one Stimulus controller + its view + system specs. Track B adds an existing controller to five `<details>` call sites + a system spec. Track C rebuilds the five `app/views/pages/*` static pages onto new shared partials (chrome/art/section/spot/footer + one CSS component), rephrasing all em-dashes out of the copy in the same pass.

**Tech Stack:** Rails 8.1, Hotwire (Stimulus over importmap, no build step for JS), Tailwind v4 (token-driven, `bin/dev` / `assets:precompile` builds it), RSpec + Cuprite (headless Chrome) system specs, FactoryBot.

**Reference artifacts (read-only, in scratchpad):**
- `…/scratchpad/design/redesign.dc.html` — the imported design (info-page layout + all SVGs).
- `…/scratchpad/design/public-pages-content.js` — the page copy (still contains em-dashes; do not paste verbatim — rephrase).
- Spec: `docs/superpowers/specs/2026-09-04-public-interaction-polish-design.md`.

**Commands:**
- One system spec file: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/<file>.rb`
- One request spec: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/pages_spec.rb`
- Lint: `bundle exec standardrb` (Ruby only; JS/ERB not linted by it)
- Full gate: `bin/ci` (definition of "green"). Faster: `bin/ci --skip-system-specs` then `bin/ci --only-system-specs`.

**Conventions:** Plain imperative commit subjects. NO Claude/Anthropic branding in commits. Never `git commit --amend` a commit that isn't yours. Work on branch `public-interaction-polish` (already created).

---

## TRACK A — Conviction vote interaction

**Files:**
- Modify: `app/javascript/controllers/conviction_controller.js` (full rewrite of timing)
- Modify: `app/views/hujahs/_vote_hero.html.erb:32-36, 111-128`
- Test: `spec/system/vote_hero_spec.rb`, helper `spec/support/pointer_helpers.rb`

### Task A1: Rewrite the conviction controller

- [ ] **Step 1: Replace `app/javascript/controllers/conviction_controller.js` with:**

```javascript
import { Controller } from "@hotwired/stimulus"

// Progressive enhancement over the plain vote forms on the single-hoojah vote hero.
// A quick TAP (release before `tap` ms) submits a NORMAL vote. A HOLD engages the
// conviction charge: a silent ARM phase (`armDelay` ms, no countdown digit) followed by
// a COUNTDOWN (`countdown` ms) showing 5→1, one digit per second; holding to the end
// commits conviction=1 (locked forever). Releasing OR leaving the button after the charge
// has engaged (past the tap threshold, before the lock) CANCELS with no vote at all.
// With JS off, each stance <form> is an ordinary POST casting a normal vote.
//
// ONE controller on the vote-hero wrapper, THREE <form>s inside (one per stance). The
// shared ring/overlay targets live on the wrapper; the per-form conviction hidden field
// is looked up INSIDE the submitting form, not via a target. Timing values are read from
// data-* attributes so system specs can shrink them to keep the suite fast.
export default class extends Controller {
  static targets = ["ring", "overlay", "chargeNum", "chargeLabel"]
  static values = {
    armDelay: { type: Number, default: 2000 },
    countdown: { type: Number, default: 5000 },
    tap: { type: Number, default: 200 },
    locked: Boolean
  }

  get totalMs() { return this.armDelayValue + this.countdownValue }

  start(event) {
    if (this.lockedValue) return
    this.form = event.currentTarget.closest("form")
    this.held = false
    this.t0 = performance.now()
    this.setChargeColor(event.currentTarget.dataset.chargeColor)
    this.setChargeLabel(event.currentTarget.dataset.stance)
    if (this.hasChargeNumTarget) this.chargeNumTarget.textContent = ""
    this.raf = requestAnimationFrame(this.tick.bind(this))
    this.timer = setTimeout(() => { this.held = true; this.commit(true) }, this.totalMs)
    if (this.hasOverlayTarget) this.overlayTarget.hidden = false
  }

  tick(now) {
    const elapsed = now - this.t0
    // Ring reflects COUNTDOWN progress only; it stays at 0 through the arm phase.
    const charge = Math.min(1, Math.max(0, (elapsed - this.armDelayValue) / this.countdownValue))
    if (this.hasRingTarget) this.ringTarget.style.setProperty("--charge", charge)
    if (this.hasChargeNumTarget) {
      // Blank during the arm phase; 5→1 during the countdown (each digit exactly 1s).
      this.chargeNumTarget.textContent =
        elapsed < this.armDelayValue ? "" : String(Math.max(1, Math.ceil((this.totalMs - elapsed) / 1000)))
    }
    if (elapsed < this.totalMs && !this.held) this.raf = requestAnimationFrame(this.tick.bind(this))
  }

  end() {
    if (this.held) return // conviction already committed by the timer
    const quickTap = (performance.now() - this.t0) < this.tapValue
    this.cancelCharge()
    if (quickTap) this.commit(false) // quick tap -> normal vote; a longer hold -> cancel, no vote
  }

  leave() { if (!this.held) this.cancelCharge() } // pointer left the button -> cancel, no vote

  cancelCharge() {
    clearTimeout(this.timer)
    cancelAnimationFrame(this.raf)
    if (this.hasOverlayTarget) this.overlayTarget.hidden = true
    if (this.hasRingTarget) this.ringTarget.style.setProperty("--charge", 0)
    if (this.hasChargeNumTarget) this.chargeNumTarget.textContent = ""
  }

  noMenu(event) { event.preventDefault() } // suppress the long-press context menu

  setChargeColor(color) {
    if (!color) return
    if (this.hasRingTarget) this.ringTarget.style.setProperty("--charge-color", color)
    if (this.hasChargeNumTarget) this.chargeNumTarget.style.color = color
    if (this.hasChargeLabelTarget) this.chargeLabelTarget.style.color = color
  }

  setChargeLabel(stance) {
    if (this.hasChargeLabelTarget && stance) {
      this.chargeLabelTarget.textContent = `charging ${stance}`
    }
  }

  commit(conviction) {
    clearTimeout(this.timer)
    cancelAnimationFrame(this.raf)
    if (!this.form) return
    // Per-form hidden field (three forms under one controller — one per stance — so
    // look it up INSIDE this.form, not via a controller target).
    const field = this.form.querySelector('input[name="conviction"]')
    if (field) field.value = conviction ? "1" : ""
    this.form.requestSubmit()
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/conviction_controller.js
git commit -m "Conviction: 2s arm + 5s countdown hold; release mid-hold cancels"
```

### Task A2: Update the vote-hero view

- [ ] **Step 1: In `app/views/hujahs/_vote_hero.html.erb`, replace the duration data attribute** (line ~35):

Change:
```erb
     data-conviction-duration-value="900"
```
to:
```erb
     data-conviction-arm-delay-value="2000"
     data-conviction-countdown-value="5000"
     data-conviction-tap-value="200"
```

- [ ] **Step 2: Update the charge overlay comment + initial digit.** Change the comment (line ~111-112) `chargeNum counts 3->0` to `chargeNum stays blank for a 2s arm, then counts 5->1 (1s each)`. Change the initial digit text on line ~123 from `>3<` to `>5<`:

```erb
        <span data-conviction-target="chargeNum" class="text-6xl font-black leading-none text-agree tabular-nums">5</span>
```

- [ ] **Step 3: Verify no other `duration` reference remains**

Run: `grep -n "conviction-duration\|counts 3" app/views/hujahs/_vote_hero.html.erb`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add app/views/hujahs/_vote_hero.html.erb
git commit -m "Vote hero: wire new conviction arm/countdown/tap values"
```

### Task A3: Rewrite the system specs (release=cancel, fast timing)

The controller reads timing live from `data-*`, so specs shrink it via `setAttribute` before the hold instead of sleeping 7s. Three cases: quick tap → normal vote (unchanged), full hold → conviction, mid-hold release → **no vote**.

- [ ] **Step 1: Replace `spec/system/vote_hero_spec.rb` with:**

```ruby
require "rails_helper"

RSpec.describe "Vote hero", type: :system, js: true do
  # Shrink the conviction timing (default 2000ms arm + 5000ms countdown) so the
  # hold-based specs stay fast. The controller reads these values live from the
  # wrapper's data-* attributes, so setting them after load takes effect on the next
  # pointerdown. arm=80ms, countdown=200ms (total 280ms lock), tap=40ms threshold.
  def shrink_conviction_timing!
    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller='conviction']")
      el.setAttribute('data-conviction-arm-delay-value', '80')
      el.setAttribute('data-conviction-countdown-value', '200')
      el.setAttribute('data-conviction-tap-value', '40')
    JS
  end

  it "taps to cast a normal vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)

    find('[data-stance="agree"]').click # instant tap, well under the 200ms default tap threshold
    expect(page).to have_content("1 vote")
    expect(h.reload.agree_count).to eq 1
    expect(h.conviction_count).to eq 0
  end

  it "holds to the end to cast a conviction vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)
    find('[data-stance="disagree"]') # ensure the hero rendered
    shrink_conviction_timing!

    hold('[data-stance="disagree"]', 0.5) # 500ms > 280ms lock
    expect(page).to have_content("1 vote")
    expect(h.reload.disagree_count).to eq 1
    expect(h.conviction_count).to eq 1
    expect(h.votes.last.conviction).to be true
  end

  it "releasing mid-hold cancels with no vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)
    find('[data-stance="agree"]') # ensure the hero rendered
    shrink_conviction_timing!

    # 150ms: past the 40ms tap threshold and the 80ms arm (into the countdown), but
    # released before the 280ms lock -> cancel, nothing recorded.
    hold('[data-stance="agree"]', 0.15)
    expect(page).to have_content("No votes yet")
    expect(h.reload.agree_count).to eq 0
    expect(h.neutral_count).to eq 0
    expect(h.disagree_count).to eq 0
    expect(h.votes.count).to eq 0
  end
end
```

- [ ] **Step 2: Run the spec**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/vote_hero_spec.rb`
Expected: 3 examples, 0 failures. If "releasing mid-hold" flakes, the `hold` node may have been replaced — it should NOT be (no submit on cancel); a failure here means the cancel path is wrong, not the test.

- [ ] **Step 3: Commit**

```bash
git add spec/system/vote_hero_spec.rb
git commit -m "Vote hero specs: fast timing, add release-cancels-no-vote case"
```

### Task A4 (review correction): suppress the native click

Review found a design bug in A1–A3: the stance buttons are `type="submit"`, so a pointer
*release* fires a trusted native `click` → the form's default submission casts a NORMAL vote,
defeating "release = cancel". Synthetic-PointerEvent specs can't see it (untrusted events don't
trigger native submit). Fix:
- Controller gains `suppressClick(event) { if (event.detail !== 0) event.preventDefault() }`,
  wired via `click->conviction#suppressClick` on the button, making the controller the sole
  submit path for pointer gestures (`requestSubmit`) while leaving keyboard clicks
  (`detail === 0`) to submit natively (accessible normal-vote path, JS-off unchanged).
- Also: re-entry guard (`this.charging`) so a second finger can't leak a timer; `disconnect()`
  clears timer/RAF; overlay hint copy changed from "reaches 0 to lock it in" to "keep holding
  to lock it in" (the digit counts 5→1, never 0).
- `spec/support/pointer_helpers.rb` switches to a TRUSTED CDP-mouse `press_hold_release` helper
  (fires the native click on release); `vote_hero_spec.rb`'s hold cases use it, and the
  mid-hold case asserts **no vote at all**. Committed as one commit on top of A1–A3.

---

## TRACK B — Dismissible dropdowns everywhere

`app/javascript/controllers/dropdown_controller.js` already exists (closes a `<details>` on outside click / Escape; attach with `data-controller="dropdown"` on the `<details>`). No changes to it. Add it to the five remaining call sites.

**Files (modify):**
- `app/views/hujahs/_card_menu.html.erb:42`
- `app/views/shared/_navbar.html.erb:42-48`
- `app/views/debates/_verdict.html.erb:158`
- `app/views/users/_profile_header.html.erb:61`
- `app/views/notifications/_notification_card.html.erb:188`
- Test: `spec/system/dropdown_dismiss_spec.rb`

### Task B1: Add `dropdown` to the four `share` menus

- [ ] **Step 1: `app/views/hujahs/_card_menu.html.erb`** — change `data-controller="share"` to `data-controller="share dropdown"`.
- [ ] **Step 2: `app/views/debates/_verdict.html.erb`** — change `data-controller="share"` to `data-controller="share dropdown"`.
- [ ] **Step 3: `app/views/users/_profile_header.html.erb`** — change `data-controller="share"` to `data-controller="share dropdown"`.
- [ ] **Step 4: Verify all three now carry both controllers**

Run: `grep -rn 'data-controller="share dropdown"' app/views/hujahs/_card_menu.html.erb app/views/debates/_verdict.html.erb app/views/users/_profile_header.html.erb`
Expected: three matches, one per file.

- [ ] **Step 5: Commit**

```bash
git add app/views/hujahs/_card_menu.html.erb app/views/debates/_verdict.html.erb app/views/users/_profile_header.html.erb
git commit -m "Dropdowns: dismiss-on-outside-click for feed/verdict/profile share menus"
```

### Task B2: Add `dropdown` to the navbar user menu + notification menu

The navbar `<details>` carries a comment asserting it needs no JS and "closes on an outside click for free" — that is not true of native `<details>`, and the product decision is now to make every dropdown dismiss on outside click. Replace the comment rather than leaving stale reasoning.

- [ ] **Step 1: In `app/views/shared/_navbar.html.erb`**, replace the comment block above the user-menu `<details>` and add the controller. Change:

```erb
        <%# `<details>` IS the menu mechanism here — the design system documents it as such
            (components/navigation/DropdownMenu.prompt.md). No Stimulus controller, and it
            closes on an outside click for free. Do not "upgrade" it to JS. %>
        <details class="relative">
```
to:
```erb
        <%# `<details>` is the menu mechanism (design system: components/navigation/
            DropdownMenu.prompt.md). The `dropdown` controller adds dismiss-on-outside-click
            + Escape to match every other menu in the app; the JS-off contract is unchanged
            (the <summary> still toggles it natively). %>
        <details class="relative" data-controller="dropdown">
```

- [ ] **Step 2: In `app/views/notifications/_notification_card.html.erb`** (line ~188), change:

```erb
    <details class="relative shrink-0">
```
to:
```erb
    <details class="relative shrink-0" data-controller="dropdown">
```

- [ ] **Step 3: Verify**

Run: `grep -n 'details class="relative" data-controller="dropdown"' app/views/shared/_navbar.html.erb && grep -n 'shrink-0" data-controller="dropdown"' app/views/notifications/_notification_card.html.erb`
Expected: one match in each file.

- [ ] **Step 4: Commit**

```bash
git add app/views/shared/_navbar.html.erb app/views/notifications/_notification_card.html.erb
git commit -m "Dropdowns: dismiss-on-outside-click for navbar user menu + notifications"
```

### Task B3: Extend the dropdown-dismiss system spec

- [ ] **Step 1: Append two examples to `spec/system/dropdown_dismiss_spec.rb`** (inside the existing `RSpec.describe "Dropdown dismissal"` block, before its final `end`):

```ruby
  it "closes the navbar user menu when tapping outside it" do
    login_as_system(author)
    visit "/"

    find("details[data-controller='dropdown'] > summary", match: :first).click
    expect(page).to have_css("nav details[data-controller='dropdown'][open]")

    find("body").click
    expect(page).to have_no_css("nav details[data-controller='dropdown'][open]")
  end

  it "closes a feed card menu when tapping outside it" do
    login_as_system(author)
    create(:hujah, user: author, body: "Feed card with a menu")
    visit "/"

    find("summary[aria-label='More options']", match: :first).click
    expect(page).to have_css("details[data-controller~='dropdown'][open]")

    find("body").click
    expect(page).to have_no_css("details[data-controller~='dropdown'][open]")
  end
```

- [ ] **Step 2: Run the spec**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/dropdown_dismiss_spec.rb`
Expected: 4 examples, 0 failures. (If the navbar summary selector is ambiguous, scope it to `nav details[data-controller='dropdown'] > summary`.)

- [ ] **Step 3: Commit**

```bash
git add spec/system/dropdown_dismiss_spec.rb
git commit -m "Dropdown dismiss spec: cover navbar user menu + feed card menu"
```

---

## TRACK C — Public static-page redesign + em-dash removal

Rebuild the five `app/views/pages/*.html.erb` onto new shared partials matching the imported
design, keeping `shared/navbar`. Rephrase every em-dash out of the copy in the same pass.
Everything is token-driven (`text-ink`, `text-ink-2`, `text-faint`, `bg-card-2`,
`border-hairline`, `text-primary`) so dark mode + schemes work for free; SVGs use `var(--…)`
inline, so **no new `@source inline(...)` entries** are needed.

**Files:**
- Create: `app/views/pages/_page_art.html.erb`, `app/views/pages/_spot.html.erb`, `app/views/pages/_section.html.erb`, `app/views/pages/_public_footer.html.erb`
- Modify: `app/views/pages/_legal_chrome.html.erb` (rewrite), `app/assets/tailwind/application.css` (add `.prose-public` in the existing `@layer components`)
- Modify: `app/views/pages/{about,tutorials,faq,privacy,terms}.html.erb`
- Test: `spec/requests/pages_spec.rb`

### Task C1: Add the `.prose-public` CSS component

- [ ] **Step 1: In `app/assets/tailwind/application.css`, inside the existing `@layer components {` block (starts ~line 149), add:**

```css
  /* Body prose for the public informational pages (pages/_section). Mirrors the imported
     design's `.prose` rules: tight paragraph rhythm, token-coloured emphasis, simple lists. */
  .prose-public p { margin: 0; }
  .prose-public p + p { margin-top: 0.75rem; }
  .prose-public em { color: var(--ink); font-style: italic; }
  .prose-public strong { color: var(--ink); font-weight: 600; }
  .prose-public ul { margin-top: 0.75rem; padding-left: 1.375rem; display: flex; flex-direction: column; gap: 0.5rem; list-style: disc; }
  .prose-public li::marker { color: var(--faint); }
```

- [ ] **Step 2: Rebuild Tailwind and confirm the class emits**

Run: `bin/rails tailwindcss:build 2>/dev/null; grep -c "prose-public" app/assets/builds/tailwind.css`
Expected: a count ≥ 1.

- [ ] **Step 3: Commit**

```bash
git add app/assets/tailwind/application.css
git commit -m "Add .prose-public component for public page body copy"
```

### Task C2: Create the per-page hero illustration partial

- [ ] **Step 1: Create `app/views/pages/_page_art.html.erb`.** Local: `art` (one of `about/tutorials/faq/privacy/terms`). Copy the five hero SVGs verbatim from `…/scratchpad/design/redesign.dc.html` (the `sc-if isAbout/isTutorials/isFaq/isPrivacy/isTerms` blocks — each a `<svg viewBox="0 0 320 160" width="360" …>`). Structure:

```erb
<%# Per-page hero illustration for the public informational pages. Lucide-style inline SVG
    stroked with theme tokens (var(--ink)/--primary/--faint/--agree/--neutral/--disagree/
    --primary-soft) so it retints in dark mode and every scheme. `art` selects the page. %>
<% case art %>
<% when "about" %>
  <svg viewBox="0 0 320 160" width="360" class="max-w-full h-auto block" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <%# …paste the About paths from redesign.dc.html isAbout block… %>
  </svg>
<% when "tutorials" %>
  <svg viewBox="0 0 320 160" width="360" class="max-w-full h-auto block" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <%# …paste the Tutorials paths… %>
  </svg>
<% when "faq" %>
  <svg viewBox="0 0 320 160" width="360" class="max-w-full h-auto block" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <%# …paste the FAQ paths… %>
  </svg>
<% when "privacy" %>
  <svg viewBox="0 0 320 160" width="360" class="max-w-full h-auto block" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <%# …paste the Privacy paths… %>
  </svg>
<% when "terms" %>
  <svg viewBox="0 0 320 160" width="360" class="max-w-full h-auto block" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <%# …paste the Terms paths… %>
  </svg>
<% end %>
```

Replace each `<%# …paste… %>` with the exact inner markup (the `<path>/<rect>/<circle>/<g>`
children) from the matching `sc-if` block in `redesign.dc.html`. Keep the `style="…display:block"`
off — the `block` class covers it. Do NOT alter the `var(--…)` colours.

- [ ] **Step 2: Commit**

```bash
git add app/views/pages/_page_art.html.erb
git commit -m "Add per-page hero illustration partial for public pages"
```

### Task C3: Create the section-spot illustration partial

- [ ] **Step 1: Create `app/views/pages/_spot.html.erb`.** Local: `spot` (one of `claim/votes/mission/compose/responses/debate`). Copy the six 48×48 spot SVGs verbatim from the `sc-if s.spotClaim/…` blocks in `redesign.dc.html`:

```erb
<%# Section-spot icon for About/Tutorials sections (56px rounded box wraps this in
    pages/_section). 40×40 inline SVG stroked with theme tokens. `spot` selects the glyph. %>
<% case spot %>
<% when "claim" %>
  <svg viewBox="0 0 48 48" width="40" height="40" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><%# …claim paths… %></svg>
<% when "votes" %>
  <svg viewBox="0 0 48 48" width="40" height="40" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><%# …votes paths… %></svg>
<% when "mission" %>
  <svg viewBox="0 0 48 48" width="40" height="40" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><%# …mission paths… %></svg>
<% when "compose" %>
  <svg viewBox="0 0 48 48" width="40" height="40" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><%# …compose paths… %></svg>
<% when "responses" %>
  <svg viewBox="0 0 48 48" width="40" height="40" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><%# …responses paths… %></svg>
<% when "debate" %>
  <svg viewBox="0 0 48 48" width="40" height="40" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><%# …debate paths… %></svg>
<% end %>
```

Replace each `<%# …paths… %>` with the exact inner markup from the matching `sc-if` block.

- [ ] **Step 2: Commit**

```bash
git add app/views/pages/_spot.html.erb
git commit -m "Add section-spot illustration partial for public pages"
```

### Task C4: Create the section + footer partials

- [ ] **Step 1: Create `app/views/pages/_section.html.erb`** (layout partial — body is yielded):

```erb
<%# One section of a public informational page. LAYOUT partial — call as
    `render layout: "pages/section", locals: {heading:, variant:, spot: nil} do … body … end`.
    :spots variant (About/Tutorials) = 56px icon box + content, no divider.
    :dividers variant (FAQ/Privacy/Terms) = single column, hairline between sections. %>
<% if variant == :spots %>
  <section class="grid grid-cols-[56px_1fr] gap-5">
    <div class="w-14 h-14 rounded-[14px] bg-card-2 flex items-center justify-center shrink-0">
      <%= render "pages/spot", spot: spot %>
    </div>
    <div class="min-w-0">
      <h2 class="mb-2.5 text-xl leading-tight font-semibold text-ink text-balance"><%= heading %></h2>
      <div class="prose-public text-ink-2 text-base leading-[1.7] text-pretty"><%= yield %></div>
    </div>
  </section>
<% else %>
  <section class="pb-7 border-b border-hairline last:border-b-0 last:pb-0">
    <h2 class="mb-2.5 text-lg leading-snug font-semibold text-ink text-balance"><%= heading %></h2>
    <div class="prose-public text-ink-2 text-base leading-[1.7] text-pretty"><%= yield %></div>
  </section>
<% end %>
```

- [ ] **Step 2: Create `app/views/pages/_public_footer.html.erb`.** Local: `current` (page key, to highlight the active link):

```erb
<%# Footer link row for the public informational pages (matches the imported design):
    the five site links centred, the current page in text-ink, the rest text-ink-2, then a
    small copyright line. `current` is the active page key. %>
<% links = [["about", "About", about_path], ["tutorials", "Tutorials", tutorials_path],
            ["faq", "FAQ", faq_path], ["privacy", "Privacy", privacy_path], ["terms", "Terms", terms_path]] %>
<footer class="mt-16 pt-8 pb-12 border-t border-hairline text-center">
  <nav aria-label="Site links" class="flex justify-center flex-wrap gap-x-3.5 gap-y-1.5 text-sm">
    <% links.each do |key, label, path| %>
      <%= link_to label, path, class: "no-underline hover:underline #{key == current ? "text-ink" : "text-ink-2"}" %>
    <% end %>
  </nav>
  <p class="mt-4 text-xs text-faint">© 2026 Hoojah</p>
</footer>
```

- [ ] **Step 3: Commit**

```bash
git add app/views/pages/_section.html.erb app/views/pages/_public_footer.html.erb
git commit -m "Add section + footer partials for public page redesign"
```

### Task C5: Rewrite `_legal_chrome` to the new layout

- [ ] **Step 1: Replace `app/views/pages/_legal_chrome.html.erb` with:**

```erb
<%# Shared chrome for the public informational pages (About / Tutorials / FAQ / Privacy /
    Terms). Centred single-column layout from the 2026 "Public Pages" redesign: the site
    navbar, then a 576px column with an illustrated centred header (per-page art via
    pages/_page_art), an eyebrow "Last updated <date>", the h1, an optional lede, the page's
    sections (yielded), and a footer link row. Call as a LAYOUT partial:
      render layout: "pages/legal_chrome",
             locals: {title:, updated:, art:, variant:, lede: nil} do … sections … end
    variant: :spots (About/Tutorials — 56px section spots, gap-10, no dividers) or
             :dividers (FAQ/Privacy/Terms — single column, gap-7, hairline between sections). %>
<%= render "shared/navbar" %>

<main class="max-w-xl mx-auto w-full px-6 pt-10">
  <header class="pb-10 border-b border-hairline">
    <div class="flex justify-center mb-8">
      <%= render "pages/page_art", art: art %>
    </div>
    <p class="mb-3 text-xs uppercase tracking-wide text-faint text-center">Last updated <%= updated %></p>
    <h1 class="text-[32px] leading-[1.15] font-extrabold tracking-tight text-ink text-center text-balance"><%= title %></h1>
    <% if local_assigns[:lede] %>
      <p class="mt-5 mx-auto max-w-[480px] text-lg leading-snug text-ink-2 text-center text-pretty"><%= lede %></p>
    <% end %>
  </header>

  <div class="flex flex-col <%= variant == :spots ? "gap-10" : "gap-7" %> pt-10">
    <%= yield %>
  </div>

  <%= render "pages/public_footer", current: art %>
</main>
```

Note: this drops the old `ui/card` wrapper and the `Last updated:` colon (the eyebrow now reads
`Last updated <date>`). Task C11 updates the request spec accordingly.

- [ ] **Step 2: Commit**

```bash
git add app/views/pages/_legal_chrome.html.erb
git commit -m "Rewrite public page chrome to centred illustrated layout"
```

### Task C6–C10: Rewrite the five page bodies (em-dash-free)

Each page calls `legal_chrome` with the right locals and renders its sections via
`render layout: "pages/section"`. Use the **existing copy** from the current
`app/views/pages/<page>.html.erb` (and `…/scratchpad/design/public-pages-content.js`), but
**remove every em-dash** by rephrasing. Contact links stay `<%= mail_to "hello@rudzainy.com", class: "text-primary" %>`.

**Em-dash rephrasing rules:** replace `—` by recasting — use a colon before a list, parentheses
for an aside, `, meaning …` for a gloss, or split into two sentences. Never leave a hyphen doing
the em-dash's job. Approved rephrasings (apply exactly these; any em-dash not listed must still
be removed the same way):

- About / "What is Hoojah?": `the Malay word <em>hujah</em> — an argument you're prepared to defend.` → `the Malay word <em>hujah</em>, meaning an argument you're prepared to defend.`
- About / "How it works": `voted on in three ways — agree, neutral, or disagree — and neutral is a real stance` → `voted on in three ways (agree, neutral, or disagree), and neutral is a real stance`
- About / "Our mission": `worse than it needs to be — not because people disagree, but because the tools give disagreement nowhere to go.` → `worse than it needs to be, not because people disagree but because the tools give disagreement nowhere to go.`
- Tutorials / "Posting…": `as a clear, single statement — the sharper and more specific it is, the better the argument it invites — and post it.` → `as a clear, single statement (the sharper and more specific it is, the better the argument it invites), then post it.`
- Tutorials / "Voting…": `remain undecided — neutral is counted and displayed alongside the others, not treated as a non-answer.` → `remain undecided. Neutral is counted and displayed alongside the others, not treated as a non-answer.`
- Tutorials / "…responses": `you pick a stance tag — agree, neutral, or disagree — so readers can see` → `you pick a stance tag (agree, neutral, or disagree) so readers can see`
- Tutorials / "…debate": `structured rounds — opening, counter, response, and closing.` → `structured rounds: opening, counter, response, and closing.`
- FAQ / "What is a hoojah?": `weigh in on — a statement you're prepared to defend.` → `weigh in on, a statement you're prepared to defend.`
- FAQ / "How does voting work?": `not an abstention — choosing it says "…", and it is counted` → `not an abstention. Choosing it says "…", and it is counted`
- FAQ / "Can the author see…": `The author of a hoojah — and everyone else — sees only the aggregate tallies:` → `The author of a hoojah, like everyone else, sees only the aggregate tallies:`
- FAQ / "What are responses?": `its own stance tag — agree, neutral, or disagree — so readers can see` → `its own stance tag (agree, neutral, or disagree) so readers can see`
- FAQ / "What is a debate?": `structured rounds — opening, counter, response, and closing.` → `structured rounds: opening, counter, response, and closing.`
- FAQ / "What are badges?": `activity on the platform — posting, participating, and engaging over time.` → `activity on the platform, such as posting, participating, and engaging over time.`
- Privacy / "Information we collect" (list items): drop the leading `Label — text` dash to `Label: text` for all five items (`Account details:`, `Content you post:`, `Votes:`, `Social graph:`, `Usage and technical data:`).
- Privacy / "Vote privacy…": `Only the aggregate counts — how many agreed, stayed neutral, and disagreed — are ever displayed.` → `Only the aggregate counts (how many agreed, stayed neutral, and disagreed) are ever displayed.`
- Privacy / "Cookies and sessions": `essential to providing the service — without it you could not stay logged in.` → `essential to providing the service; without it you could not stay logged in.`
- Terms / "Acceptable use" (list items): `spam — including …` → `spam, including …`; `attempt to defeat vote privacy — probing, correlating, or otherwise trying …` → `attempt to defeat vote privacy by probing, correlating, or otherwise trying …`
- Terms / "Your content and licence": `You own the content you post on Hoojah — your hoojahs, responses, debate turns, and profile content.` → `You own the content you post on Hoojah: your hoojahs, responses, debate turns, and profile content.`
- Terms / "Debates and the spectator verdict": `manipulate verdicts — including through multiple accounts or coordinated inauthentic voting — is a breach` → `manipulate verdicts (including through multiple accounts or coordinated inauthentic voting) is a breach`
- Terms / "Moderation…": `should survive termination — including content licences for already-shared content, disclaimers, and limitation of liability — survive it.` → `should survive termination (including content licences for already-shared content, disclaimers, and limitation of liability) survive it.`

#### Task C6: About (`app/views/pages/about.html.erb`) — variant :spots, has lede

- [ ] **Step 1: Replace the file with** (rephrased copy above; sections in order with spots `claim`, `votes`, `mission`):

```erb
<%= render layout: "pages/legal_chrome", locals: {title: "About Hoojah", updated: "30 August 2026", art: "about", variant: :spots, lede: "Hoojah is a Malaysian social debate platform built around structured disagreement. Instead of an endless feed of opinions shouted past each other, Hoojah gives every claim a shape: you post it, others take a stance on it, and the strongest arguments can be settled in a proper one-on-one debate."} do %>
  <%= render layout: "pages/section", locals: {heading: "What is Hoojah?", variant: :spots, spot: "claim"} do %>
    <p>Hoojah takes its name from the Malay word <em>hujah</em>, meaning an argument you're prepared to defend. A hoojah is a claim you post for others to weigh in on. Once it's up, people can vote on it, respond to it with their own stance, or challenge an argument beneath it to a formal debate. Everything on the platform is organised around that single idea: making disagreement legible and productive rather than noisy.</p>
  <% end %>
  <%= render layout: "pages/section", locals: {heading: "How it works", variant: :spots, spot: "votes"} do %>
    <p>Every hoojah can be voted on in three ways (agree, neutral, or disagree), and neutral is a real stance, not an abstention. Votes are a secret ballot: only the aggregate tallies are ever shown, and nobody can see how an individual voted. Readers add responses, each carrying its own stance tag, which thread into a tree of argument under the original claim. When two people want to settle a point directly, any argument can be escalated into a turn-based debate: a challenger and an opponent take alternating turns through opening, counter, response, and closing rounds while everyone else watches and, at the end, casts a verdict on who was more convincing.</p>
  <% end %>
  <%= render layout: "pages/section", locals: {heading: "Our mission", variant: :spots, spot: "mission"} do %>
    <p>We think online conversation is worse than it needs to be, not because people disagree but because the tools give disagreement nowhere to go. Hoojah's goal is to make good-faith argument the default: to reward the person who makes the better case, to keep votes honest by keeping them anonymous, and to give a genuine debate a beginning, a middle, and an end. If you've ever wished a thread could actually resolve something, Hoojah is built for you.</p>
  <% end %>
<% end %>
```

- [ ] **Step 2: Commit** `git add app/views/pages/about.html.erb && git commit -m "Redesign About page; remove em-dashes"`

#### Task C7: Tutorials (`tutorials.html.erb`) — variant :spots, has lede

- [ ] **Step 1: Replace the file** — locals `{title: "Getting Started", updated: "30 August 2026", art: "tutorials", variant: :spots, lede: "New to Hoojah? This short guide walks you through the four things you'll do most: posting a claim, voting on one, responding with your stance, and taking an argument to a debate."}`. Four sections with spots `compose`, `votes`, `responses`, `debate`, using the rephrased Tutorials copy above. Same `render layout: "pages/section"` structure as C6. Keep the `<strong>agree</strong>/<strong>disagree</strong>/<strong>neutral</strong>` emphasis in the voting section.
- [ ] **Step 2: Commit** `git add app/views/pages/tutorials.html.erb && git commit -m "Redesign Tutorials page; remove em-dashes"`

#### Task C8: FAQ (`faq.html.erb`) — variant :dividers, no lede

- [ ] **Step 1: Replace the file** — locals `{title: "Frequently Asked Questions", updated: "26 August 2026", art: "faq", variant: :dividers}` (no `lede`). Eleven sections (headings unchanged from the current file), each `render layout: "pages/section", locals: {heading: "…", variant: :dividers}` with the rephrased FAQ body. Keep the `<em>hujah</em>` and the `mail_to` in the last section.
- [ ] **Step 2: Commit** `git add app/views/pages/faq.html.erb && git commit -m "Redesign FAQ page; remove em-dashes"`

#### Task C9: Privacy (`privacy.html.erb`) — variant :dividers, no lede

- [ ] **Step 1: Replace the file** — locals `{title: "Privacy Policy", updated: "26 August 2026", art: "privacy", variant: :dividers}`. Twelve sections (headings unchanged). The "Information we collect" section keeps its `<ul>` (use the same `list-disc list-outside pl-5 mt-2 space-y-1` markup as today OR rely on `.prose-public ul` — either renders; prefer keeping the explicit `<ul>` for the five items) with each item's leading `—` changed to `:`. Keep the three `mail_to` links.
- [ ] **Step 2: Commit** `git add app/views/pages/privacy.html.erb && git commit -m "Redesign Privacy page; remove em-dashes"`

#### Task C10: Terms (`terms.html.erb`) — variant :dividers, no lede

- [ ] **Step 1: Replace the file** — locals `{title: "Terms of Service", updated: "26 August 2026", art: "terms", variant: :dividers}`. Twelve numbered sections (headings unchanged). The "Acceptable use" section keeps its `<ul>` + the trailing "We may remove content…" `<p>`, with the two list-item em-dashes rephrased. Keep the `mail_to` in section 3 and section 12.
- [ ] **Step 2: Commit** `git add app/views/pages/terms.html.erb && git commit -m "Redesign Terms page; remove em-dashes"`

### Task C11: Update + extend the pages request spec (em-dash guard)

- [ ] **Step 1: In `spec/requests/pages_spec.rb`, change both `expect(response.body).to include("Last updated:")` lines** (the eyebrow dropped the colon) to:

```ruby
        expect(response.body).to include("Last updated ")
```

- [ ] **Step 2: Add an em-dash guard.** Inside the `pages.each do |path, expected|` → `describe "GET #{path}"` block, add a third example:

```ruby
      it "contains no em-dashes (copy policy)" do
        get path
        expect(response.body).not_to include("—")
      end
```

- [ ] **Step 3: Run the pages spec**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/pages_spec.rb`
Expected: all examples pass (5 pages × 3 examples + the sidebar-footer example = 16). If the em-dash guard fails for a page, an em-dash survived — grep that page's rendered body and rephrase.

- [ ] **Step 4: Sanity-check the whole `pages` view dir for stray em-dashes**

Run: `grep -rl $'—' app/views/pages/`
Expected: no output.

- [ ] **Step 5: Commit** `git add spec/requests/pages_spec.rb && git commit -m "Pages spec: match new eyebrow, guard against em-dashes"`

---

## FINAL: full gate

- [ ] **Step 1: StandardRB (Ruby)**

Run: `bundle exec standardrb`
Expected: no offenses. (ERB/JS are not covered by StandardRB; only the specs/helpers are.)

- [ ] **Step 2: Full CI**

Run: `bin/ci`
Expected: all gates green (StandardRB, Brakeman, bundler-audit, Tailwind build, full RSpec incl. system specs). If the shared test DB is busy (`PG::ObjectInUse`), run `bin/ci --skip-system-specs` then `bin/ci --only-system-specs` separately.

- [ ] **Step 3: Confirm no interpolated Tailwind classes were introduced.** Track C uses only static utilities + `var(--…)` inline in SVG, so the `@source inline(...)` safelist should be untouched.

Run: `git diff master -- app/assets/tailwind/application.css | grep -c "@source inline"`
Expected: `0` (only the `.prose-public` component was added, no new safelist lines).

---

## Self-review notes (coverage vs spec)
- Track A: arm(2000)+countdown(5000)+tap(200) values, digit 5→1, ring=countdown-only, release=cancel, JS-off unchanged → Tasks A1–A2; three spec cases incl. the new cancel case → A3. ✔
- Track B: five call sites (card/navbar/verdict/profile/notification) → B1–B2; navbar stale comment replaced → B2; spec covers navbar + feed card → B3. ✔
- Track C: 576px centred illustrated layout, spots vs dividers, lede on About/Tutorials only, footer, dark-mode/scheme via tokens → C1–C5; five page rewrites with all em-dashes rephrased → C6–C10; "Last updated:" colon + em-dash guard → C11. ✔
- Gates: StandardRB/Brakeman/bundler-audit/Tailwind/RSpec via `bin/ci`; safelist-untouched check. ✔
