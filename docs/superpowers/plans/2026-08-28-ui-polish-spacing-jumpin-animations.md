# UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App-wide polish — consistent spacing, feed-card interaction changes (un-linked title, persistent "Jump in", conviction count), navbar mobile tweak, and an expressive reduced-motion-safe microanimation layer.

**Architecture:** Server-rendered Hotwire; edits are ERB views, `application.css` (Tailwind v4 tokens/keyframes), `DesignSystemHelper`, and a few Stimulus controllers. Slices A/B are deterministic (exact code + system specs). Slices C/D are audit-driven: a Fable spacing audit and a find-animation-opportunities catalog produce the concrete per-surface edits, applied under fixed guardrails + acceptance criteria.

**Tech Stack:** Rails 8.1, Turbo/Stimulus (importmap), Tailwind v4 (`tailwindcss-rails`), RSpec + Cuprite system specs, Lucide icons.

**Spec:** `docs/superpowers/specs/2026-08-28-ui-polish-spacing-jumpin-animations-design.md`

**Global guardrails (every task):**
- Tailwind v4: interpolated/arbitrary classes need `@source inline(...)`; same-family utilities resolve by bundle order — use `ui/_card`/`ui/_menu` locals, don't fight baked paddings. ERB `<%# %>` comments ARE scanned — never name a utility class in a comment you don't want compiled.
- After comment-only or safelist edits, md5 the built bundle to confirm intended change (positive control).
- Preserve invariants: secret-ballot (`conviction_count` aggregate-only), per-post visibility, block/private gates. No new read surface.
- Ruby is mise-managed: prefix with `mise exec ruby@3.4.9 --` if needed. Shared Postgres test DB — run one spec file at a time, never the full suite in parallel.
- StandardRB formats Ruby. No Claude/Anthropic branding in commits. Commit per task.

---

## Slice A — Navbar mobile (Trending label)

### Task A1: Hide the mobile Trending label on small phones

**Files:**
- Modify: `app/views/shared/_navbar.html.erb` (~L148-150, the `lg:hidden` Trending button)
- Modify (if needed): `app/assets/tailwind/application.css` (`@source inline(...)` safelist)
- Test: `spec/system/navbar_trending_mobile_spec.rb` (create)

- [ ] **Step 1: Write the failing test**

```ruby
require "rails_helper"

# The mobile Trending nav button (lg:hidden) shows an icon + label. On small
# phones the label is hidden (icon-only); it returns at >=420px.
RSpec.describe "Navbar trending label on mobile", type: :system, js: true do
  it "hides the Trending label on a small phone and shows it on a large one" do
    login_as_system(create(:user))

    page.current_window.resize_to(360, 780) # small phone
    visit "/"
    label = find("a[aria-label='Trending'] span", text: "Trending", visible: :all)
    expect(label).not_to be_visible

    page.current_window.resize_to(500, 900) # large phone / small tablet, still lg:hidden
    visit "/"
    expect(find("a[aria-label='Trending'] span", text: "Trending")).to be_visible
  end
end
```

- [ ] **Step 2: Run to verify it fails** — `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/navbar_trending_mobile_spec.rb` — Expected: FAIL (label visible at 360px).

- [ ] **Step 3: Edit the view.** In the mobile Trending `link_to` block, change the label span from `<span class="text-sm">Trending</span>` to:

```erb
        <span class="text-sm hidden min-[420px]:inline">Trending</span>
```

- [ ] **Step 4: Safelist check.** Build the bundle (`mise exec ruby@3.4.9 -- bin/rails tailwindcss:build`) and grep it for the `min-[420px]:inline` rule. If absent, add `min-[420px]:inline` to the `@source inline(...)` block in `application.css`, rebuild, confirm present. (Arbitrary variants are often not emitted from a single ERB use.)

- [ ] **Step 5: Run to verify pass** — same rspec command — Expected: PASS.

- [ ] **Step 6: Commit** — `Hide navbar Trending label on small phones`

---

## Slice B — Feed card (`app/views/hujahs/_hujah_card.html.erb`)

### Task B1: Un-link the body; keep hashtags/mentions clickable

**Files:**
- Modify: `app/views/hujahs/_hujah_card.html.erb` (L51-55)
- Test: `spec/system/feed_card_interaction_spec.rb` (create)

- [ ] **Step 1: Write the failing test**

```ruby
require "rails_helper"

RSpec.describe "Feed card interaction", type: :system, js: true do
  it "does not wrap the body in a link but keeps hashtags and mentions clickable" do
    mentioned = create(:user, username: "sitir")
    author = create(:user)
    create(:hujah, user: author, body: "free transit for #kl and @sitir by 2030")

    login_as_system(create(:user))
    visit "/"

    card = find("[data-testid='hujah-card']", match: :first)
    # Body text present, but NOT inside an <a> to the hujah page:
    expect(card).to have_css(".hujah-body")
    expect(card).to have_no_css("a.hujah-body, a > .hujah-body")
    # Hashtag + mention are still anchors:
    within(card) do
      expect(page).to have_link("#kl")
      expect(page).to have_link("@sitir")
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails** — `... rspec spec/system/feed_card_interaction_spec.rb` — Expected: FAIL (`.hujah-body` is currently inside an `<a>`).

- [ ] **Step 3: Edit the view.** Replace L51-55:

```erb
    <div class="px-4 pt-3 pb-0">
      <%= link_to hujah_path(hujah.slug), class: "block text-ink no-underline" do %>
        <div class="hujah-body text-lg leading-snug"><%= format_body(hujah.body) %></div>
      <% end %>
    </div>
```
with:
```erb
    <%# Body is deliberately NOT a link (2026 polish): tapping the claim text should
        select, not navigate — and wrapping it in an <a> nested the tag/mention anchors
        format_body injects, which is invalid HTML. The thread is reached via the
        "Jump in" pill and the response count below. Tags/mentions stay clickable. %>
    <div class="px-4 pt-3 pb-0">
      <div class="hujah-body text-ink text-lg leading-snug"><%= format_body(hujah.body) %></div>
    </div>
```

- [ ] **Step 4: Run to verify pass** — Expected: PASS.

- [ ] **Step 5: Commit** — `Un-link feed card body; keep hashtags and mentions clickable`

### Task B2: Persistent "Jump in →" with smart target + conviction count

**Files:**
- Modify: `app/views/hujahs/_hujah_card.html.erb` (footer, L65-83)
- Test: extend `spec/system/feed_card_interaction_spec.rb`

- [ ] **Step 1: Add failing tests**

```ruby
  it "shows Jump in on a plain card linking to the thread, and the conviction count when > 0" do
    author = create(:user)
    h = create(:hujah, user: author, body: "a plain claim about kopi", conviction_count: 2)

    login_as_system(create(:user))
    visit "/"
    card = find("[data-testid='hujah-card']", match: :first)
    within(card) do
      expect(page).to have_link("Jump in", href: hujah_path(h.slug))
      expect(page).to have_text("2") # conviction count chip
    end
  end

  it "points Jump in at the debate room when a live debate exists" do
    author = create(:user); opp = create(:user)
    h = create(:hujah, user: author, body: "a debated claim about durian")
    debate = create(:debate, hujah: h, challenger: author, opponent: opp, status: :active)

    login_as_system(create(:user))
    visit "/"
    card = find("[data-testid='hujah-card']", match: :first)
    within(card) { expect(page).to have_link("Jump in", href: debate_path(debate.slug)) }
  end
```
(If `create(:debate, status: :active)` needs both stances / `rounds_limit`, match the factory's real shape — see spec/factories/debates.rb.)

- [ ] **Step 2: Run to verify failure** — Expected: FAIL (Jump in only renders with active_debate; no conviction chip).

- [ ] **Step 3: Edit the footer.** Replace the footer block (L65-83) so the counts row always includes an optional conviction chip and the Jump-in pill always renders with a smart target:

```erb
    <div class="px-4 py-2 flex items-center text-sm text-ink-2">
      <%= link_to hujah_path(hujah.slug), class: "flex items-center text-ink-2 no-underline" do %>
        <%= lucide_icon("bar-chart-3", class: "w-4 h-4") %>
        <span class="ml-1"><%= hujah.total_votes %></span>
        <span class="mx-2">·</span>
        <%= lucide_icon("message-circle", class: "w-4 h-4") %>
        <span class="ml-1"><%= hujah.children.size %></span>
      <% end %>

      <% if hujah.conviction_count.to_i > 0 %>
        <span class="ml-3 flex items-center text-primary" aria-label="Conviction votes">
          <%= lucide_icon("heart", class: "w-4 h-4") %>
          <span class="ml-1"><%= hujah.conviction_count %></span>
        </span>
      <% end %>

      <% if hujah.active_debate %>
        <span class="ml-3 flex items-center text-disagree" aria-label="Live debate on this hujah">
          <%= lucide_icon("swords", class: "w-4 h-4") %>
        </span>
      <% end %>

      <%# Jump in is the primary way into the thread now the body is un-linked:
          a live debate jumps to the debate room, otherwise to the hujah thread. %>
      <%= link_to (hujah.active_debate ? debate_path(hujah.active_debate.slug) : hujah_path(hujah.slug)),
            class: "#{ds_button_classes(variant: :outline, tone: "primary", size: :sm)} ml-auto" do %>
        Jump in <%= lucide_icon("arrow-right", class: "w-3.5 h-3.5") %>
      <% end %>
    </div>
```

- [ ] **Step 4: Run to verify pass** — Expected: PASS (all 4 examples in the file).

- [ ] **Step 5: Guard** — run `spec/system/smoke_spec.rb`, `spec/requests/hujahs_index_spec.rb` (frozen `data-testid`), and any feed spec; all green. StandardRB clean.

- [ ] **Step 6: Commit** — `Persistent Jump in with smart target; conviction count in feed card footer`

---

## Slice D-foundation — Motion tokens (before spacing/animation)

### Task D0: Reduced-motion scaffold + motion tokens

**Files:**
- Modify: `app/assets/tailwind/application.css` (keyframes/tokens block)
- Test: `spec/system/reduced_motion_spec.rb` (create) + `TailwindBuild` assertion

- [ ] **Step 1:** Inventory existing keyframes (`grep -n "@keyframes" app/assets/tailwind/application.css` — expect `hbreathe`, possibly `hrise`). Reuse; do not duplicate.
- [ ] **Step 2:** Add a global reduced-motion guard near the top of the stylesheet:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

- [ ] **Step 3:** Add any missing motion keyframes the catalog (Task D-audit) will need (defer specifics to that task; this task only lands the reduced-motion guard + confirms the keyframe inventory).
- [ ] **Step 4:** System spec asserts an animated element (the live-pill dot) exists and that the reduced-motion rule is present in the built bundle via `TailwindBuild.emitted?`. Commit — `Add reduced-motion guard and confirm motion-token inventory`.

---

## Slice C — Spacing/padding/margin consistency pass (audit-driven)

### Task C-audit: Fable spacing audit → concrete per-surface diff

**Deliverable:** a checklist (committed under `docs/superpowers/plans/`) enumerating each spacing change as `file:line — current → proposed — reason`, grouped by surface. NO code edits in this task.

- [ ] **Step 1:** Dispatch a **Fable architect** subagent (model: fable, effort: medium) to audit spacing across: `ui/_card`, `ds_card_classes`, `ui/_menu`/`ds_menu_item_classes`, `_navbar`, feed card + `_vote_bars`, `hujahs/show` + composers (`_compose_form`, `_inline_composer`, `_stance_picker`), devise auth views, `users/_profile_header`/`_profile_edit`/`_profile_tabs`, `debates/show` + `_debate_turn`/`_turn_composer`/`_debate_status`/`_debate_actions`, `_notification_card`. It must: report the current spacing scale (`--space-1..6`), list inconsistencies/cramped/loose spots, propose edits to ONE coherent scale (only proposing a token-scale change with an explicit reason), and flag any Tailwind bundle-order/safelist risk per edit.
- [ ] **Step 2:** Review the audit; trim to a focused, low-risk set. Commit the checklist.

### Task C1..Cn: Apply spacing edits per surface

For EACH surface group in the audit checklist:
- [ ] Screenshot the surface before (`browse screenshot --selector`).
- [ ] Apply the audit's exact edits (use `ui/_card`/`ui/_menu` locals where padding is involved; add `@source inline(...)` for any new interpolated/arbitrary class).
- [ ] Screenshot after; visually confirm the intended change and no layout breakage.
- [ ] Run that surface's system spec(s) if any; StandardRB clean.
- [ ] Commit per surface group — `Normalize spacing: <surface>`.

**Acceptance:** consistent inter-element rhythm within/across surfaces on the token scale; no regressions in existing system specs; bundle md5 changes only where intended.

---

## Slice D — Microanimations (catalog-driven)

### Task D-audit: find-animation-opportunities catalog

- [ ] **Step 1:** Invoke the **find-animation-opportunities** skill over the app (feed, show, debate room, menus, dialogs, tabs, vote widgets, Turbo-Stream inserts). It is read-only and returns a prioritized proposal with exact elements + values.
- [ ] **Step 2:** Select the approved expressive set (press feedback; Turbo-Stream enter transitions for turns/replies/vote-bar/notifications; menu + `<dialog>` open; tab-underline slide; vote-cast accent via existing charge-ring/boom; number roll-up). Commit the catalog under `docs/superpowers/plans/`.

### Task D1..Dn: Implement each animation

For EACH approved animation:
- [ ] Prefer CSS-only (keyframes/transitions/`@starting-style`) in `application.css`; safelist any interpolated class.
- [ ] Where Stimulus is required (e.g. number roll-up, optimistic vote accent), dispatch a **better-stimulus** subagent to author/adjust the controller (single responsibility, values API, `disconnect` cleanup — no leaked timers/listeners).
- [ ] Verify with a system spec where behavior is assertable (e.g. a Turbo-Stream insert adds the animation class; a control has the transition), and manually via `browse` + a GIF for the reviewer.
- [ ] Confirm the reduced-motion guard neutralizes it (`prefers-reduced-motion` emulation).
- [ ] Commit per animation — `Animate: <what>`.

**Acceptance:** motion reads as purposeful and consistent; all disabled under reduced-motion; no console errors; `bin/ci` green.

---

## Final
- [ ] Full `design-review` pass across changed surfaces (screenshots).
- [ ] `bin/ci` green.
- [ ] `superpowers:finishing-a-development-branch`.

## Self-review notes
- Spec coverage: A (navbar) ✓ A1; B (body unlink ✓ B1, Jump in + conviction ✓ B2); C (spacing) ✓ C-audit + C1..n; D (animations) ✓ D0 + D-audit + D1..n. Out-of-scope items (impressions, watcher counts) excluded.
- C/D edits are intentionally audit-produced (design work): the plan fixes the process, guardrails, and acceptance criteria rather than inventing per-pixel values blind.
