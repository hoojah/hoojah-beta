# Hoojah 2026 Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the new-post composer and single-hujah "argument" page to the Hoojah 2026 design (responsive mobile-first), adding a runtime theme/scheme system, per-post visibility, an allow-debates toggle, conviction-lock voting, and a real hashtag system.

**Architecture:** Keep Tailwind v4 utilities but chain `@theme` colors onto runtime CSS variables switched by `data-theme`/`data-scheme` on `<html>`, so existing utilities retint per theme/scheme. Net-new mechanics are additive DB columns + a new hashtags table, layered onto the existing `cast_vote` transaction and Pundit policies. Hold-to-charge conviction and the inline composers are Stimulus progressive-enhancements over server-rendered `button_to`/`form_with` baselines that still work with JS off.

**Tech Stack:** Rails 8.1, Hotwire (Turbo + Stimulus over importmap, no Node build), Tailwind v4 (`tailwindcss-rails`), Devise, Pundit, Pagy, RSpec + FactoryBot + Cuprite, Postgres, strong_migrations, StandardRB.

**Design source of truth:** `docs/superpowers/specs/assets/hoojah-2026-newpost.html` and `…-single-hoojah.html` (extracted mockup regions committed in Task 0) and the full spec `docs/superpowers/specs/2026-08-24-hoojah-2026-redesign-design.md`. Views must match these mockups visually; this plan is authoritative on the Rails wiring (form fields, helpers, `data-*` hooks, Turbo targets).

**Conventions reminder:** Commit subjects imperative, **no Claude/Anthropic branding**. Run one RSpec suite at a time (shared Postgres). Ruby is mise-managed — prefix `mise exec ruby@3.4.9 --` if mise isn't active. StandardRB formats Ruby (`bundle exec standardrb --fix`). Tailwind bundle is gitignored — system/CSS-asserting specs call `TailwindBuild.once!`.

---

## Track & task overview

- **Track 0 — Setup:** commit mockup reference assets.
- **Track 1 — Theming & tokens:** CSS variable bridge, `<html>` attrs + no-FOUC script, `theme_controller`, navbar toggle.
- **Track 2 — Migrations & models:** `visibility`, `allow_debates`, `conviction`(+count), validations, `cast_vote` conviction, visibility scoping, `voted_by?`, policies.
- **Track 3 — Hashtags:** `Hashtag` + join, body parser, `TagsController` + route, `format_body` linkify, suggested-tags query.
- **Track 4 — Surface 1 (new post):** full-page composer rebuild + inline feed composer + `composer_controller`.
- **Track 5 — Surface 2 (single hujah):** header/hero, vote hero + `conviction_controller`, responses/debates restyle, argument composer + `argument_composer_controller` + respond overlay.

Tracks 1–3 are foundational and independent (parallelizable). Tracks 4–5 consume them. Within each track, tasks are ordered and each ends in a green commit.

---

## Track 0 — Setup

### Task 0.1: Commit mockup reference assets

**Files:**
- Create: `docs/superpowers/specs/assets/hoojah-2026-newpost.html`
- Create: `docs/superpowers/specs/assets/hoojah-2026-single-hoojah.html`
- Create: `docs/superpowers/specs/assets/hoojah-2026-tokens.css`

- [ ] **Step 1: Copy the extracted mockup regions into the repo.** The compose-overlay + inline-composer markup and the full single-hoojah screen (author hero, vote hero, charge/boom overlays, debates, responses, argument composer, respond overlay) were extracted from `Hoojah 2026.dc.html`. Place the new-post region in `hoojah-2026-newpost.html`, the single-hoojah region in `hoojah-2026-single-hoojah.html`, and the `:root`/`[data-theme]`/`[data-scheme]` token blocks (spec §2.4) in `hoojah-2026-tokens.css`. These are read-only references for view work — they are HTML/CSS so Tailwind would scan them; keep them under `docs/` which is already `@source not`-excluded (verify the exclusion covers `docs/superpowers/specs/assets/`).

- [ ] **Step 2: Commit.**
```bash
git add docs/superpowers/specs/assets/
git commit -m "Add Hoojah 2026 mockup reference assets for the redesign"
```

---

## Track 1 — Theming & tokens

### Task 1.1: Add the runtime token bridge to Tailwind

**Files:**
- Modify: `app/assets/tailwind/application.css` (`@theme` block ~lines 130–189; `@source inline` safelist ~line 101; `@layer base` ~line 218)
- Test: `spec/assets/tailwind_tokens_spec.rb` (new)

- [ ] **Step 1: Write the failing test.** Assert the built bundle emits theme-aware utilities and the dark/scheme override blocks. Uses the `TailwindBuild` helper (`spec/support/tailwind_build.rb`).
```ruby
require "rails_helper"

RSpec.describe "Tailwind 2026 tokens" do
  before(:all) { TailwindBuild.once! }

  it "chains stance utilities onto runtime --agree/--neutral/--disagree vars" do
    css = TailwindBuild.css
    expect(css).to include("--color-agree: var(--agree)")
    expect(css).to include("--color-neutral: var(--neutral)")
    expect(css).to include("--color-disagree: var(--disagree)")
  end

  it "defines Spectrum defaults on :root and a dark override" do
    css = TailwindBuild.css
    expect(css).to match(/:root\s*\{[^}]*--agree:\s*#0ea5a4/m)
    expect(css).to match(/\[data-theme="dark"\][^{]*\{[^}]*--agree:\s*#2dd4cf/m)
  end

  it "defines Signal and Ballot scheme overrides" do
    css = TailwindBuild.css
    expect(css).to include('[data-scheme="signal"]')
    expect(css).to include('[data-scheme="ballot"]')
  end
end
```
> NOTE: confirm `TailwindBuild` exposes the compiled CSS (the support file defines `.emitted?`; add/use a `.css` reader if needed — see `spec/support/tailwind_build.rb`). If the helper only offers `emitted?(str)`, rewrite the asserts as `expect(TailwindBuild.emitted?("--color-agree: var(--agree)")).to be true`.

- [ ] **Step 2: Run it, expect FAIL.**
Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/assets/tailwind_tokens_spec.rb`
Expected: FAIL (tokens not defined yet).

- [ ] **Step 3: Indirect the theme-aware colors through runtime vars using `@theme inline`.** Put the var-referencing (theme/scheme-aware) tokens in a SEPARATE `@theme inline { … }` block — `inline` makes Tailwind emit `var(--agree)` **directly into each utility** (`.bg-agree{background:var(--agree)}`) so it resolves per-element, instead of declaring `--color-agree` only on `:root` (which would only work because the attrs sit on `<html>` and would silently stay light under any subtree override). Keep the fixed neutrals the views still use in the ordinary `@theme` block.
```css
/* theme/scheme-aware — inline so utilities reference the runtime var directly */
@theme inline {
  --color-primary: var(--primary);
  --color-primary-soft: var(--primary-soft);
  --color-agree: var(--agree);
  --color-neutral: var(--neutral);
  --color-disagree: var(--disagree);
  --color-agree-soft: var(--agree-soft);
  --color-neutral-soft: var(--neutral-soft);
  --color-disagree-soft: var(--disagree-soft);
  --color-surface: var(--surface);
  --color-card: var(--card);
  --color-card-2: var(--card-2);
  --color-ink: var(--ink);
  --color-ink-2: var(--ink-2);
  --color-faint: var(--faint);
  --color-hairline: var(--hairline);
  --color-field: var(--field);
  --color-unread: var(--unread);
}
/* fixed — stay in the ordinary @theme block: --color-black, --color-grey,
   --color-light-grey, --color-white, gray-*, red-*, --color-read, text sizes, radii… */
```

- [ ] **Step 4: Define the runtime tokens (outside `@theme`, top of file after imports).** Paste the Spectrum/light `:root` block, the `[data-theme="dark"]` block, and the `signal`/`ballot` scheme blocks (light + dark) verbatim from `docs/superpowers/specs/assets/hoojah-2026-tokens.css` (spec §2.4). Also port the keyframes `hpop hfloat hboom hray hbar hbreathe hrise`.
  - Merge the new tokens into the file's EXISTING `:root` block (which already holds `--surface-page`, `--fg-body`, etc.). Rewire those existing semantic aliases to the runtime vars so dark mode paints: `--surface-page: var(--surface); --surface-card: var(--card); --fg-body: var(--ink); --fg-muted: var(--ink-2); --fg-faint: var(--faint); --border-hairline: var(--hairline); --border-field: var(--field);` — but define `--surface/--card/--ink/…` themselves in the base `:root` (Spectrum/light) and override only those in the `[data-theme]`/`[data-scheme]` blocks.
  - The existing `@layer base` sets `body { background: var(--surface-page) }` — since `--surface-page` now chains to `var(--surface)`, dark mode works with no change there. Also add `--color-unread: var(--unread)` / `--unread: var(--neutral)` chaining so the notification unread color follows the scheme (keep `--color-read`).

- [ ] **Step 5: Extend the safelist ONLY for newly-interpolated utilities.** Keep `@source inline("{bg,text,border}-{agree,neutral,disagree,primary}")`. If any new interpolation is introduced (e.g. `bg-{stance}-soft`), add `@source inline("{bg,text,border}-{agree,neutral,disagree,primary}-soft")`. Do not add rows for utilities used as fixed names.

- [ ] **Step 6: Run tests, expect PASS.**
Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/assets/tailwind_tokens_spec.rb`
Expected: PASS.

- [ ] **Step 7: md5 guard.** Confirm a comment-only edit doesn't move the bundle and a positive control does (per CLAUDE.md Tailwind gotcha #1). Then commit.
```bash
git add app/assets/tailwind/application.css spec/assets/tailwind_tokens_spec.rb
git commit -m "Add Hoojah 2026 runtime theme/scheme token bridge to Tailwind"
```

### Task 1.2: Root attributes + no-FOUC script in the layout

**Files:**
- Modify: `app/views/layouts/application.html.erb` (the `<html>` tag and `<head>`)
- Test: `spec/system/theming_spec.rb` (new, `js: true`)

- [ ] **Step 1: Write the failing system test.**
```ruby
require "rails_helper"

RSpec.describe "Theming", :js do
  it "defaults to light+spectrum and persists a dark toggle across reload" do
    visit root_path
    expect(page).to have_css('html[data-theme="light"]')
    find('[data-theme-target="toggle"]').click
    expect(page).to have_css('html[data-theme="dark"]')
    visit root_path # reload
    expect(page).to have_css('html[data-theme="dark"]') # from localStorage, set before paint
  end
end
```

- [ ] **Step 2: Run it, expect FAIL** (no toggle, no attrs).
Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/theming_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Add server-default attributes + the no-FOUC script.** Change `<html>` to `<html data-theme="light" data-scheme="spectrum">`. Immediately inside `<head>`, BEFORE `stylesheet_link_tag`, add a nonce'd inline script (the layout already uses `content_security_policy_nonce` for Drift):
```erb
<script nonce="<%= content_security_policy_nonce %>">
  (function () {
    try {
      var t = localStorage.getItem("hoojah-theme");
      var s = localStorage.getItem("hoojah-scheme");
      var el = document.documentElement;
      if (t === "light" || t === "dark") el.setAttribute("data-theme", t);
      if (s === "spectrum" || s === "signal" || s === "ballot") el.setAttribute("data-scheme", s);
    } catch (e) {}
  })();
</script>
```
> Contains no Tailwind utility strings, so the scan can't mint stray rules. `<html>` is not replaced by Turbo, so the attributes persist across Turbo visits.

- [ ] **Step 4:** (toggle control comes in Task 1.3; this test will pass once 1.3 lands. To keep this task green on its own, assert only the default attrs here and move the toggle+persist assertion into Task 1.3's test. Split the spec accordingly.)

- [ ] **Step 5: Run the default-attrs assertion, expect PASS; commit.**
```bash
git add app/views/layouts/application.html.erb spec/system/theming_spec.rb
git commit -m "Set default data-theme/data-scheme and add no-FOUC theme script"
```

### Task 1.3: `theme_controller` + navbar toggle

**Files:**
- Create: `app/javascript/controllers/theme_controller.js`
- Modify: `app/views/shared/_navbar.html.erb` (add the toggle pill)
- Test: `spec/system/theming_spec.rb` (toggle + persist + scheme cycle)

- [ ] **Step 1: Write the failing test** (toggle dark, reload persists; cycle scheme to signal, reload persists).
```ruby
it "cycles scheme and persists" do
  visit root_path
  find('[data-theme-target="scheme"]').click # spectrum -> signal
  expect(page).to have_css('html[data-scheme="signal"]')
  visit root_path
  expect(page).to have_css('html[data-scheme="signal"]')
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement `theme_controller`.**
```javascript
import { Controller } from "@hotwired/stimulus"

// Toggles data-theme (light/dark) and cycles data-scheme (spectrum/signal/ballot)
// on <html>, persisting both to localStorage. The no-FOUC head script re-applies
// them before paint on the next load.
export default class extends Controller {
  static targets = ["toggle", "scheme"]
  static schemes = ["spectrum", "signal", "ballot"]

  toggleTheme() {
    const el = document.documentElement
    const next = el.getAttribute("data-theme") === "dark" ? "light" : "dark"
    el.setAttribute("data-theme", next)
    try { localStorage.setItem("hoojah-theme", next) } catch (e) {}
  }

  cycleScheme() {
    const el = document.documentElement
    const schemes = this.constructor.schemes
    const cur = el.getAttribute("data-scheme") || "spectrum"
    const next = schemes[(schemes.indexOf(cur) + 1) % schemes.length]
    el.setAttribute("data-scheme", next)
    try { localStorage.setItem("hoojah-scheme", next) } catch (e) {}
  }
}
```

- [ ] **Step 4: Add the toggle pill to the navbar** wrapped in `data-controller="theme"`, with a sun/moon button (`data-action="theme#toggleTheme" data-theme-target="toggle"`) and a small scheme-swatch button (`data-action="theme#cycleScheme" data-theme-target="scheme"`). Use Lucide icons (`lucide-rails` `lucide_icon "sun-moon"`). Match the mockup's pill styling with `bg-card`, `border-hairline`, `text-ink` utilities.

- [ ] **Step 5: Run tests, expect PASS; commit.**
```bash
git add app/javascript/controllers/theme_controller.js app/views/shared/_navbar.html.erb spec/system/theming_spec.rb
git commit -m "Add theme/scheme toggle controller and navbar control"
```

### Task 1.4: Dark-mode safety for shared chrome

> **Why:** the toggle is site-wide (it flips `<html data-theme>`), but the legacy app paints with **pinned-hex** utilities — `bg-white` (~30 uses), `bg-gray-50/100/200`, `text-black` — so in dark mode, body-inherited text goes light inside cards that stay white → invisible text. We make the SHARED primitives + common chrome theme-aware here, and explicitly DEFER full per-screen dark polish of non-focus screens (auth, profile, notifications, debate room) to a HANDOVER follow-up. We do NOT claim full dark coverage.

**Files:**
- Modify: `app/assets/tailwind/application.css` (neutral remap), `app/helpers/design_system_helper.rb` (`ds_card_classes`/button surfaces if they bake `bg-white`), `app/views/ui/_card.html.erb`, `app/views/ui/_menu.html.erb`, `app/views/shared/_navbar.html.erb`, `app/views/hujahs/_vote_bars.html.erb`, `app/views/hujahs/_stance_picker.html.erb`
- Test: `spec/system/theming_spec.rb` (computed-style assertion)

- [ ] **Step 1: Remap the neutral surface tokens (not white).** In `@theme inline`, chain the Tailwind neutrals the chrome leans on onto theme vars so borders/fills adapt: `--color-gray-50: var(--card-2); --color-gray-100: var(--hairline); --color-gray-200: var(--field);`. **Keep `--color-white` FIXED** — `text-white` carries the stance-button glyph inversion (safelisted) and must stay white. Keep `--color-black` fixed but note `text-black` won't adapt (handled by the sweep below).

- [ ] **Step 2: Sweep the SHARED surfaces from `bg-white`→`bg-card` and `text-black`→`text-ink`.** Only in the primitives/chrome that appear on the redesigned surfaces: `ui/_card` (or `ds_card_classes` if the white is baked there — read `app/helpers/design_system_helper.rb` first), `ui/_menu`, `shared/_navbar`, `hujahs/_vote_bars`, `hujahs/_stance_picker`. Do NOT chase every legacy screen. If `bg-white` is produced by `ds_card_classes`, change it there once (covers all cards). Preserve `text-white` glyph inversions.

- [ ] **Step 3: Add a computed-style assertion** to `spec/system/theming_spec.rb` proving the cascade actually wins (not just that strings exist):
```ruby
it "resolves --agree per theme+scheme at runtime" do
  visit root_path
  spectrum_light = page.evaluate_script("getComputedStyle(document.documentElement).getPropertyValue('--agree').trim()")
  expect(spectrum_light).to eq("#0ea5a4")
  find('[data-theme-target="toggle"]').click # -> dark
  dark = page.evaluate_script("getComputedStyle(document.documentElement).getPropertyValue('--agree').trim()")
  expect(dark).to eq("#2dd4cf")
end
```

- [ ] **Step 4: Run the theming system spec, expect PASS; commit.**
```bash
git add app/assets/tailwind/application.css app/helpers/design_system_helper.rb app/views/ui app/views/shared/_navbar.html.erb app/views/hujahs/_vote_bars.html.erb app/views/hujahs/_stance_picker.html.erb spec/system/theming_spec.rb
git commit -m "Make shared chrome theme-aware for dark mode"
```
> HANDOVER note (Task 6.1 Step 4): auth, profile, notifications, and the debate room are NOT dark-polished this pass — they inherit the tokens but may show residual light surfaces in dark mode. Follow-up.

---

## Track 2 — Migrations & models

### Task 2.1: Migration — per-post visibility & allow_debates

**Files:**
- Create: `db/migrate/<ts>_add_visibility_and_allow_debates_to_hujahs.rb`
- Modify: `db/schema.rb` (generated)
- Test: `spec/models/hujah_spec.rb`

- [ ] **Step 1: Write the migration** (safe adds: defaulted non-null columns on PG are metadata-only).
```ruby
class AddVisibilityAndAllowDebatesToHujahs < ActiveRecord::Migration[8.1]
  def change
    add_column :hujahs, :visibility, :integer, null: false, default: 0
    add_column :hujahs, :allow_debates, :boolean, null: false, default: true
    add_column :hujahs, :conviction_count, :integer, null: false, default: 0
  end
end
```

- [ ] **Step 2: Run migration + prepare test DB.**
```bash
bin/rails db:migrate && bin/rails db:test:prepare
```
Expected: three columns added; `db/schema.rb` updated.

- [ ] **Step 3: Add the enum + helpers to `Hujah`.** After the associations:
```ruby
# Per-post visibility for TOP-LEVEL claims (replies inherit their parent). Enum keys
# avoid the reserved words public/private. Default = visible_public.
enum :visibility, { visible_public: 0, followers_only: 1, private_only: 2 }, prefix: :visibility
```

- [ ] **Step 4: Write model specs** for defaults (`Hujah.new.visibility_visible_public?` true, `allow_debates` true, `conviction_count` 0). Run, expect PASS. Commit.
```bash
git add db/migrate db/schema.rb app/models/hujah.rb spec/models/hujah_spec.rb
git commit -m "Add visibility, allow_debates, conviction_count to hujahs"
```

### Task 2.2: Migration — vote conviction flag

**Files:**
- Create: `db/migrate/<ts>_add_conviction_to_votes.rb`
- Modify: `app/models/vote.rb`, `db/schema.rb`
- Test: `spec/models/vote_spec.rb`

- [ ] **Step 1: Migration.**
```ruby
class AddConvictionToVotes < ActiveRecord::Migration[8.1]
  def change
    add_column :votes, :conviction, :boolean, null: false, default: false
  end
end
```

- [ ] **Step 2: Migrate + prepare; commit.** (No model logic yet — `cast_vote` change is Task 2.4.)
```bash
bin/rails db:migrate && bin/rails db:test:prepare
git add db/migrate db/schema.rb && git commit -m "Add conviction flag to votes"
```

### Task 2.3: Body length validation (top-level only) + `voted_by?`

**Files:**
- Modify: `app/models/hujah.rb`
- Test: `spec/models/hujah_spec.rb`

- [ ] **Step 1: Write failing specs.**
```ruby
it "requires >= 8 chars for a top-level claim" do
  h = build(:hujah, parent: nil, body: "short")
  expect(h).not_to be_valid
end
it "allows a short reply" do
  parent = create(:hujah)
  h = build(:hujah, parent: parent, body: "ok")
  expect(h).to be_valid
end
it "voted_by? reflects a cast vote" do
  h = create(:hujah); u = create(:user)
  expect(h.voted_by?(u)).to be false
  h.cast_vote(by: u, choice: 1)
  expect(h.voted_by?(u)).to be true
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement.** Replace `validates :body, presence: true` with:
```ruby
validates :body, presence: true
validates :body, length: { minimum: 8 }, if: -> { parent_id.nil? }

# Has this user cast any vote on this hoojah? Used to gate replying (must vote first)
# and to render the argument composer's locked state.
def voted_by?(user)
  user.present? && votes.exists?(user_id: user.id)
end
```

- [ ] **Step 4: Run, expect PASS; commit.**
```bash
git add app/models/hujah.rb spec/models/hujah_spec.rb
git commit -m "Add 8-char minimum for top-level claims and Hujah#voted_by?"
```

### Task 2.4: `cast_vote` conviction lock

**Files:**
- Modify: `app/models/hujah.rb` (`cast_vote`)
- Test: `spec/models/hujah_spec.rb`

- [ ] **Step 1: Write failing specs.**
```ruby
describe "#cast_vote conviction" do
  let(:h) { create(:hujah) }
  let(:u) { create(:user) }

  it "locks a conviction vote and refuses later changes" do
    h.cast_vote(by: u, choice: 1, conviction: true)
    expect(h.reload.conviction_count).to eq 1
    h.cast_vote(by: u, choice: 3) # attempt to switch
    expect(h.votes.find_by(user: u).vote.last).to eq 1 # unchanged
    expect(h.reload.agree_count).to eq 1
    expect(h.disagree_count).to eq 0
  end

  it "counts a conviction vote as exactly 1 toward its stance" do
    h.cast_vote(by: u, choice: 2, conviction: true)
    expect(h.reload.neutral_count).to eq 1
  end

  it "upgrades an existing non-conviction vote to conviction without double-counting" do
    h.cast_vote(by: u, choice: 1)
    h.cast_vote(by: u, choice: 1, conviction: true) # same stance, now lock it
    expect(h.reload.agree_count).to eq 1
    expect(h.conviction_count).to eq 1
    expect(h.votes.find_by(user: u).conviction).to be true
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Rewrite `cast_vote`** to accept `conviction:` and honor the lock. **Use a row lock** (`votes.lock.find_by`) so a concurrent same-stance upgrade can't double-increment `conviction_count`, and NEVER let the stance-change branch write `conviction` back to false over a committed lock (a locked row early-returns under the lock anyway, but write it defensively):
```ruby
def cast_vote(by:, choice:, conviction: false)
  choice = choice.to_i
  return unless COUNTER_FOR.key?(choice)

  transaction do
    # `.lock` takes a FOR UPDATE row lock so the conviction? re-check below reads
    # committed state — two concurrent upgrades can't both see conviction=false and
    # double-count. (A unique index on votes[hujah_id,user_id] is on the backlog to
    # also close the concurrent-first-vote double-row race; see HANDOVER.)
    existing = votes.lock.find_by(user_id: by.id)
    if existing
      return if existing.conviction? # locked forever — no stance change, no re-lock

      previous = existing.vote.last
      if previous == choice
        # Same stance: allow upgrading a plain vote to a conviction (locked) vote.
        if conviction
          existing.update!(conviction: true)
          increment!(:conviction_count)
        end
        return
      end

      # Never overwrite an existing lock with false (defensive — locked rows already
      # early-returned above): OR the flags.
      new_conviction = existing.conviction || conviction
      existing.update!(vote: existing.vote + [choice], conviction: new_conviction)
      increment!(:conviction_count) if conviction && !existing.conviction
      decrement!(COUNTER_FOR[previous]) if COUNTER_FOR.key?(previous)
      increment!(COUNTER_FOR[choice])
    else
      votes.create!(user: by, vote: [choice], conviction: conviction)
      increment!(COUNTER_FOR[choice])
      increment!(:conviction_count) if conviction
      # Privacy: new_vote notification carries NO subject_user_id (secret ballot).
      Notification.create!(user_id: user_id, category: :new_vote, hujah_id: id)
    end
  end
end
```
> A locked re-vote is a **silent** no-op (not a domain error) — the vote hero's `locked-value` makes it unreachable in the UI, and the votes controller renders its normal Turbo Stream (the widget just re-renders unchanged). Documented deviation from spec §3.7. Add a concurrent unique index on `votes [hujah_id, user_id]` (+ `rescue ActiveRecord::RecordNotUnique`) to `HANDOVER.md` backlog.

- [ ] **Step 4: Run, expect PASS; run the full model spec to catch regressions.**
Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_spec.rb`

- [ ] **Step 5: Commit.**
```bash
git add app/models/hujah.rb spec/models/hujah_spec.rb
git commit -m "Support conviction-lock votes in Hujah#cast_vote"
```

### Task 2.5: Per-post visibility scoping

> **SECURITY-CRITICAL.** Per-post visibility must be closed on EVERY surface that renders a claim, not just the HTML feed/show. The Fable architecture audit found five additional leak surfaces; all are included below. Missing any one serves a `followers_only`/`private_only` claim to strangers.

**Files:**
- Modify: `app/models/hujah.rb` (`visible_to?`, `self.trending`), `app/controllers/hujahs_controller.rb` (`index` both branches), `app/policies/hujah_policy.rb` (`show?`, `vote?`), `app/controllers/api/v1/hujahs_controller.rb` (`index`), `app/controllers/users_controller.rb` (`show`)
- Test: `spec/models/hujah_spec.rb`, `spec/requests/hujahs_spec.rb`, `spec/requests/api/v1/hujahs_spec.rb`, `spec/requests/users_spec.rb`, `spec/requests/trending_spec.rb` (add/extend as they exist)

- [ ] **Step 1: Write failing specs** covering the matrix: `private_only` claim visible only to author; `followers_only` visible to accepted followers + author; `visible_public` unchanged (still gated by author account privacy).
```ruby
describe "#visible_to? per-post" do
  let(:author) { create(:user) }
  let(:follower) { create(:user) }
  let(:stranger) { create(:user) }
  before { create(:follow, :accepted, follower: follower, followed: author) }

  it "private_only claim: author only" do
    h = create(:hujah, user: author, visibility: :private_only)
    expect(h.visible_to?(author)).to be true
    expect(h.visible_to?(follower)).to be false
    expect(h.visible_to?(stranger)).to be false
  end

  it "followers_only claim: author + accepted followers" do
    h = create(:hujah, user: author, visibility: :followers_only)
    expect(h.visible_to?(follower)).to be true
    expect(h.visible_to?(stranger)).to be false
  end
end
```
> Adapt the follow factory/trait to the project's actual factory (check `spec/factories/` for the accepted-follow trait; the map noted follows are accepted-only via a status).

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Extend `Hujah#visible_to?`** to AND the per-post rule with the account-level rule:
```ruby
# A hoojah is visible when BOTH the author is visible to the viewer (account privacy,
# Slice 7b) AND the per-post visibility permits it. A REPLY (parent_id present) is gated
# by the parent AND by the reply author's OWN account privacy — dropping the latter
# regresses Slice 7b Gate 6 (a private user's reply under a public claim must stay hidden
# from non-followers; the API show + notification cards rely on this).
def visible_to?(viewer)
  return parent.visible_to?(viewer) && user.visible_to?(viewer) if parent_id
  return false unless user.visible_to?(viewer)

  case visibility
  when "visible_public" then true
  when "followers_only" then viewer == user || user.accepted_follower?(viewer)
  when "private_only" then viewer == user
  else false
  end
end
```
> Confirm `User#accepted_follower?` exists (the map/User grep shows `accepted_follower?(viewer)` used inside `visible_to?`). If it's private, expose it or add a thin predicate. **Add a spec** pinning: a `private` user's reply under a public claim is NOT visible to a stranger, IS visible to an accepted follower.

- [ ] **Step 4: Scope the HTML feed.** In `HujahsController#index`, on the GLOBAL/anonymous branch, after the existing `users: {private: false}` filter add:
```ruby
# Per-post visibility (2026): the global/anonymous feed shows only visible_public claims.
global = global.where(visibility: :visible_public)
```
On the FOLLOWING branch, followers may see `followers_only` too, AND the viewer must still see their OWN `private_only` claims (don't over-hide — `timeline_for` already includes `user.id`):
```ruby
Hujah.timeline_for(current_user)
  .where("hujahs.visibility IN (0, 1) OR hujahs.user_id = ?", current_user.id)
  .includes(:user).order(updated_at: :desc)
```

- [ ] **Step 5: `HujahPolicy#show?` and `#vote?`** — gate both through the model rule so a stranger can't read OR vote on (bump counters / probe existence of) a non-public claim by guessing its slug:
```ruby
def show? = record.visible_to?(user)
def vote? = user.present? && record.visible_to?(user)
```

- [ ] **Step 6: Close the JSON API index (CRITICAL leak).** `app/controllers/api/v1/hujahs_controller.rb#index` currently serves every public-author hujah. Add the same per-post filter:
```ruby
# Per-post visibility (2026): the public API index is a hard boundary — visible_public only.
.where(visibility: :visible_public)
```
Add a request spec: `GET /api/v1/...index` never includes a `private_only`/`followers_only` claim. (Api show already gates via `visible_to?`, now fixed for replies in Step 3.)

- [ ] **Step 7: Close trending (HIGH leak).** In `Hujah.trending` (`hujah.rb`), the candidate query filters only `users: {private: false}`. Add `.where(visibility: :visible_public)` to the candidate scope so a `followers_only` claim with activity never lands on public `/trending`. Add/extend a trending spec.

- [ ] **Step 8: Scope the profile page (HIGH leak).** `UsersController#show` sets `@hujahs = @user.hujahs…` for any viewer. Scope per viewer:
```ruby
# Self sees all; an accepted follower sees public + followers_only; everyone else public only.
@hujahs =
  if current_user == @user
    @user.hujahs
  elsif user_signed_in? && @user.accepted_follower?(current_user)
    @user.hujahs.where(visibility: [:visible_public, :followers_only])
  else
    @user.hujahs.where(visibility: :visible_public)
  end
# …preserve any existing parent_id/order/includes chaining on @hujahs.
```
Read the current `UsersController#show` first and keep its existing scoping (top-level only, ordering, pagination). Add a request spec.

- [ ] **Step 9: Run all touched model + request specs, expect PASS.** Update existing feed/show/api/profile/trending specs that assumed all claims are public. Commit.
```bash
git add app/models/hujah.rb app/controllers/hujahs_controller.rb app/controllers/api/v1/hujahs_controller.rb app/controllers/users_controller.rb app/policies/hujah_policy.rb spec/
git commit -m "Enforce per-post visibility across feed, show, API, trending, profile, and vote"
```

### Task 2.6: allow_debates gate + vote-to-respond gate in policies

**Files:**
- Modify: `app/policies/debate_policy.rb` (`create?`), `app/policies/hujah_policy.rb` (`create?`)
- Test: `spec/policies/debate_policy_spec.rb`, `spec/policies/hujah_policy_spec.rb`

- [ ] **Step 1: Write failing policy specs.**
```ruby
# DebatePolicy: no challenge when the claim disallows debates
it "forbids create when the hoojah disallows debates" do
  claim = create(:hujah, allow_debates: false)
  reply = create(:hujah, parent: claim, user: create(:user))
  debate = build(:debate, hujah: claim, opponent: reply.user, challenger: create(:user))
  expect(DebatePolicy.new(debate.challenger, debate).create?).to be false
end

# HujahPolicy: cannot reply until you've voted on the parent
it "forbids a reply before the replier has voted on the parent" do
  parent = create(:hujah); replier = create(:user)
  reply = build(:hujah, parent: parent, user: replier)
  expect(HujahPolicy.new(replier, reply).create?).to be false
  parent.cast_vote(by: replier, choice: 1)
  expect(HujahPolicy.new(replier, reply).create?).to be true
end
```
> Adjust to the actual `Debate` factory shape (challenger/opponent/hujah). Check `spec/factories/debates.rb`.

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: `DebatePolicy#create?`** — add the allow-debates clause. `record` is a Debate; reach its hoojah:
```ruby
def create? = user.present? &&
  !user.hidden_user_ids.include?(record.opponent_id) &&
  record.hujah.allow_debates?
```
> Confirm `Debate belongs_to :hujah` (the map shows `@hujah.debates`, so yes). If the association name differs, use it.

- [ ] **Step 3b: Close the concluded-debate transcript leak (MEDIUM).** `debates/show.html.erb` renders `@debate.hujah.body`, so a concluded public debate on a `followers_only` claim shows that claim to anyone. In `DebatePolicy`, the NON-participant branch of `show?` and the concluded set in `Scope#resolve` must also require the claim be visible:
```ruby
def show? = record.participant?(user) ||
  (record.concluded? && record.challenger.visible_to?(user) &&
   record.opponent.visible_to?(user) && record.hujah.visible_to?(user))
```
And in `Scope#resolve`, add `&& d.hujah.visible_to?(user)` to the `concluded_visible` select. Add a policy spec: a concluded debate on a `followers_only` claim is not visible to a stranger.

- [ ] **Step 4: `HujahPolicy#create?`** — require a prior vote on the parent for replies:
```ruby
def create?
  return false unless user.present?
  return true if record.parent_id.nil?
  parent = record.parent
  parent && !user.hidden_user_ids.include?(parent.user_id) &&
    parent.visible_to?(user) && parent.voted_by?(user)
end
```

- [ ] **Step 5: Run policy specs + the existing request specs that reply** (these will now need the replier to vote first — update those fixtures/specs). Expect PASS. Commit.
```bash
git add app/policies spec/
git commit -m "Gate debates by allow_debates and replies by a prior vote"
```

---

## Track 3 — Hashtags

### Task 3.1: Hashtag + join tables and models

**Files:**
- Create: `db/migrate/<ts>_create_hashtags.rb`, `db/migrate/<ts>_create_hashtag_hujahs.rb`
- Create: `app/models/hashtag.rb`, `app/models/hashtag_hujah.rb`
- Modify: `app/models/hujah.rb` (association), `db/schema.rb`
- Test: `spec/models/hashtag_spec.rb`

- [ ] **Step 1: Migrations.**
```ruby
class CreateHashtags < ActiveRecord::Migration[8.1]
  def change
    create_table :hashtags do |t|
      t.string :name, null: false            # canonical, lower-cased
      t.string :display, null: false         # first-seen original casing, for chips
      t.integer :hujahs_count, null: false, default: 0
      t.timestamps
    end
    add_index :hashtags, :name, unique: true
  end
end
```
```ruby
class CreateHashtagHujahs < ActiveRecord::Migration[8.1]
  def change
    create_table :hashtag_hujahs do |t|
      t.references :hashtag, null: false, foreign_key: true
      t.references :hujah, null: false, foreign_key: true
      t.timestamps
    end
    add_index :hashtag_hujahs, [:hashtag_id, :hujah_id], unique: true
  end
end
```

- [ ] **Step 2: Migrate + prepare.**
```bash
bin/rails db:migrate && bin/rails db:test:prepare
```

- [ ] **Step 3: Models.**
```ruby
# app/models/hashtag.rb
class Hashtag < ApplicationRecord
  has_many :hashtag_hujahs, dependent: :destroy
  has_many :hujahs, through: :hashtag_hujahs
  validates :name, presence: true, uniqueness: true

  def self.canonical(raw) = raw.to_s.downcase
end
```
```ruby
# app/models/hashtag_hujah.rb
class HashtagHujah < ApplicationRecord
  belongs_to :hashtag, counter_cache: :hujahs_count
  belongs_to :hujah
end
```
Add to `Hujah`: `has_many :hashtag_hujahs, dependent: :destroy` and `has_many :hashtags, through: :hashtag_hujahs`.

- [ ] **Step 4: Spec** the models + counter cache. Run, expect PASS. Commit.
```bash
git add db/ app/models/hashtag.rb app/models/hashtag_hujah.rb app/models/hujah.rb spec/models/hashtag_spec.rb
git commit -m "Add Hashtag and HashtagHujah models with a join and counter"
```

### Task 3.2: Parse hashtags from the body

**Files:**
- Modify: `app/models/hujah.rb` (parser + callback)
- Test: `spec/models/hujah_spec.rb`

- [ ] **Step 1: Write failing specs.**
```ruby
describe "hashtag parsing" do
  it "extracts and links #tags on save, case-insensitively and idempotently" do
    h = create(:hujah, body: "Free transit for #KlangValley and #klangvalley please today")
    expect(h.hashtags.pluck(:name)).to contain_exactly("klangvalley")
    expect(h.hashtags.first.display).to eq "KlangValley"
    h.update!(body: "Now about #Belanjawan spending decisions here")
    expect(h.reload.hashtags.pluck(:name)).to contain_exactly("belanjawan")
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement.** Mirror `MENTION_RE`/`notify_mentions`:
```ruby
# #hashtag pattern — same lookbehind guard as mentions so `a#b` isn't a tag.
# Unicode letters allowed (Malay names); digits and underscore permitted.
HASHTAG_RE = /(?<!\w)#(\p{L}[\p{L}0-9_]*)/

after_save_commit :sync_hashtags

# Reconcile this hoojah's hashtag joins with the tags currently in its body. Runs
# on create and edit (unlike notify_mentions which is create-only) because the tag
# set must track edits. Canonical name is lower-cased; display keeps first casing.
def sync_hashtags
  raw = body.to_s.scan(HASHTAG_RE).flatten.uniq(&:downcase).first(10)
  wanted = raw.index_by { |r| Hashtag.canonical(r) }
  Hashtag.transaction do
    tags = wanted.map do |name, original|
      Hashtag.create_with(display: original).find_or_create_by!(name: name)
    end
    self.hashtags = tags # replaces the join set; counter_cache adjusts
  end
end
```
> `after_save_commit` avoids running inside `cast_vote`'s transaction. `self.hashtags = tags` diffs the join. Confirm `counter_cache` decrements on removal (it does via `has_many :through` replacement destroying join rows).

- [ ] **Step 4: Run, expect PASS; commit.**
```bash
git add app/models/hujah.rb spec/models/hujah_spec.rb
git commit -m "Parse and sync #hashtags from hoojah bodies"
```

### Task 3.3: Tag feed route, controller, view

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/tags_controller.rb`, `app/views/tags/show.html.erb`, `app/views/tags/show.turbo_stream.erb`
- Test: `spec/requests/tags_spec.rb`

- [ ] **Step 1: Failing request spec.**
```ruby
it "lists public claims carrying the tag" do
  tagged = create(:hujah, body: "Cheaper fares on the #MRT line for everyone please")
  create(:hujah, body: "Unrelated claim with enough length here")
  get "/t/mrt"
  expect(response).to have_http_status(:ok)
  expect(response.body).to include(tagged.slug)
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Route** (near the feed routes, with a comment per convention):
```ruby
# Hashtag feed (2026). Public, countless-paginated top-level claims carrying :name
# (canonical lower-cased). Addressed by tag name, not id, like the rest of the app.
get "/t/:name", to: "tags#show", as: :tag
```

- [ ] **Step 4: Controller** (mirror `index` visibility rules):
```ruby
class TagsController < ApplicationController
  def show
    skip_authorization
    @tag = Hashtag.find_by!(name: Hashtag.canonical(params[:name]))
    base = @tag.hujahs.where(parent_id: nil).where(visibility: :visible_public)
      .joins(:user).where(users: {private: false}).includes(:user).order(updated_at: :desc)
    base = base.where.not(user_id: current_user.hidden_user_ids) if user_signed_in?
    @pagy, @hujahs = pagy(:countless, base)
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  rescue ActiveRecord::RecordNotFound
    skip_authorization
    head :not_found
  end
end
```

- [ ] **Step 5: Views** — `tags/show.html.erb` reuses the feed card partial (`hujahs/_hujah_card`) inside the standard navbar layout with a `#PublicTransport`-style header; `tags/show.turbo_stream.erb` mirrors `hujahs/index.turbo_stream.erb` (load-more append). Match the feed's markup so cards look identical.

- [ ] **Step 6: Run, expect PASS; commit.**
```bash
git add config/routes.rb app/controllers/tags_controller.rb app/views/tags/ spec/requests/tags_spec.rb
git commit -m "Add hashtag feed at /t/:name"
```

### Task 3.4: Linkify #hashtags in `format_body`

**Files:**
- Modify: `app/helpers/hujahs_helper.rb` (`format_body`, line ~25)
- Test: `spec/helpers/hujahs_helper_spec.rb`

**Critical:** `format_body` (in `HujahsHelper`, NOT ApplicationHelper) tokenizes `@mentions` with U+E000/U+E001 private-use markers on the RAW text BEFORE `simple_format`/`auto_link`, then restores anchors AFTER — a deliberate security design (never gsub links over rendered HTML). Hashtags MUST use the identical marker pattern with a distinct marker pair (U+E002/U+E003), or an `#` inside an autolinked URL could splice markup.

- [ ] **Step 1: Failing helper spec.**
```ruby
require "rails_helper"
RSpec.describe HujahsHelper, type: :helper do
  it "linkifies #hashtags to the tag feed and preserves @mentions" do
    html = helper.format_body("hey @nurul about #KlangValley transit")
    expect(html).to include('href="/u/nurul"')
    expect(html).to include('href="/t/klangvalley"')
    expect(html).to include(">#KlangValley</a>")
  end
  it "does not linkify a # inside a URL" do
    html = helper.format_body("see https://x.com/page#frag now")
    expect(html).not_to include('href="/t/frag"')
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Add a hashtag marker pass mirroring the mention one.** Add the constants and extend `format_body`:
```ruby
HASHTAG_OPEN = [0xE002].pack("U")
HASHTAG_CLOSE = [0xE003].pack("U")
HASHTAG_TOKEN_RE = /#{HASHTAG_OPEN}#(\p{L}[\p{L}0-9_]*)#{HASHTAG_CLOSE}/

def format_body(text)
  tokenized = text.to_s
    .gsub(Hujah::MENTION_RE) { "#{MENTION_OPEN}@#{$1}#{MENTION_CLOSE}" }
    .gsub(Hujah::HASHTAG_RE) { "#{HASHTAG_OPEN}##{$1}#{HASHTAG_CLOSE}" }
  linked = auto_link(simple_format(tokenized), html: {target: "_blank", rel: "noopener"})
  linked
    .gsub(MENTION_TOKEN_RE) do
      handle = $1
      %(<a href="/u/#{ERB::Util.url_encode(handle)}" class="text-primary">@#{ERB::Util.html_escape(handle)}</a>)
    end
    .gsub(HASHTAG_TOKEN_RE) do
      name = $1
      %(<a href="/t/#{ERB::Util.url_encode(name.downcase)}" class="text-primary">##{ERB::Util.html_escape(name)}</a>)
    end
    .delete(MENTION_OPEN + MENTION_CLOSE + HASHTAG_OPEN + HASHTAG_CLOSE)
    .html_safe
end
```
> `Hujah::HASHTAG_RE` is defined in Task 3.2. The `.downcase` in the href matches `Hashtag.canonical`.

- [ ] **Step 4: Run, expect PASS; commit.**
```bash
git add app/helpers/hujahs_helper.rb spec/helpers/hujahs_helper_spec.rb
git commit -m "Linkify #hashtags in format_body"
```

---

## Track 4 — Surface 1: New post

> Visual target: `docs/superpowers/specs/assets/hoojah-2026-newpost.html`. Each view task: **read the current partial AND the mockup asset first**, then rewrite markup to the mockup while preserving the Rails bindings named in the task. Use `bg-card`/`text-ink`/`border-hairline`/etc. utilities (Task 1.1 tokens), never raw hex, and never a concrete `bg-#0ea5a4`.

### Task 4.1: Permit new fields in the composer

**Files:**
- Modify: `app/controllers/hujahs_controller.rb` (`compose_params`)
- Test: `spec/requests/hujahs_spec.rb`

- [ ] **Step 1: Failing request spec** — posting `hujah[visibility]=private_only` and `hujah[allow_debates]=0` persists both.
```ruby
it "persists visibility and allow_debates on create" do
  sign_in create(:user)
  post "/hoojah", params: { hujah: { body: "A brand new claim about transit", visibility: "private_only", allow_debates: "0" } }
  h = Hujah.order(:created_at).last
  expect(h.visibility).to eq "private_only"
  expect(h.allow_debates).to be false
end
```

- [ ] **Step 2: Run, expect FAIL** (unpermitted params ignored).

- [ ] **Step 3: Permit the fields.**
```ruby
def compose_params
  params.require(:hujah).permit(:body, :parent_id, :vote, :visibility, :allow_debates)
end
```
> `visibility` arrives as an enum string ("private_only"); Rails enum assignment accepts it. `allow_debates` "0"/"1" casts to boolean.

- [ ] **Step 4: Run, expect PASS; commit.**
```bash
git add app/controllers/hujahs_controller.rb spec/requests/hujahs_spec.rb
git commit -m "Permit visibility and allow_debates on the compose form"
```

### Task 4.2: `composer_controller` (Stimulus)

**Files:**
- Create: `app/javascript/controllers/composer_controller.js`
- Test: exercised by the system specs in 4.3/4.4.

- [ ] **Step 1: Implement the controller.** Handles: min-char enable/disable of the Post button, the visibility menu (open/close + select, writing a hidden field + label), inserting a suggested hashtag into the textarea, and the collapsed→expanded→maximize transitions for the inline feed variant.
```javascript
import { Controller } from "@hotwired/stimulus"

// Drives both composer variants (full-page + inline feed). Progressive enhancement:
// the <form> submits fine with JS off; this only gates the Post button, toggles the
// visibility menu, inserts hashtag chips, and expands the inline pill.
export default class extends Controller {
  static targets = ["body", "post", "menu", "visLabel", "visField", "collapsed", "expanded"]
  static values = { min: { type: Number, default: 8 }, requireMin: { type: Boolean, default: true } }

  connect() { this.sync() }

  sync() {
    if (!this.hasPostTarget || !this.hasBodyTarget) return
    const ok = !this.requireMinValue || this.bodyTarget.value.trim().length >= this.minValue
    this.postTarget.disabled = !ok
    this.postTarget.toggleAttribute("data-ready", ok)
  }

  input() { this.sync(); this.autogrow() }

  autogrow() {
    const el = this.bodyTarget
    el.style.height = "auto"
    el.style.height = el.scrollHeight + "px"
  }

  toggleMenu() { this.menuTarget.hidden = !this.menuTarget.hidden }

  select(event) {
    const value = event.currentTarget.dataset.value
    const label = event.currentTarget.dataset.label
    this.visFieldTarget.value = value
    if (this.hasVisLabelTarget) this.visLabelTarget.textContent = label
    this.menuTarget.hidden = true
  }

  addTag(event) {
    event.preventDefault()
    const tag = event.currentTarget.dataset.tag
    const el = this.bodyTarget
    const sep = el.value.length && !el.value.endsWith(" ") ? " " : ""
    el.value = el.value + sep + "#" + tag + " "
    el.focus()
    this.sync(); this.autogrow()
  }

  expand() { if (this.hasCollapsedTarget) { this.collapsedTarget.hidden = true; this.expandedTarget.hidden = false; this.bodyTarget.focus() } }
}
```

- [ ] **Step 2: Commit** (no standalone JS unit test; behavior verified in 4.3/4.4).
```bash
git add app/javascript/controllers/composer_controller.js
git commit -m "Add composer_controller for the 2026 hoojah composer"
```

### Task 4.3: Rebuild the full-page composer

**Files:**
- Modify: `app/views/hujahs/_compose_form.html.erb`, `app/views/hujahs/new.html.erb`
- Modify: `app/controllers/hujahs_controller.rb` (`new` — set `@suggested_tags`)
- Test: `spec/system/composer_spec.rb` (new, `js: true`)

- [ ] **Step 1: Failing system spec.**
```ruby
require "rails_helper"

RSpec.describe "New hoojah composer", :js do
  it "keeps Post disabled under 8 chars and enables past it" do
    sign_in create(:user)
    visit new_hujah_path
    expect(page).to have_button("Post", disabled: true)
    fill_in "hujah[body]", with: "Public transport should be free"
    expect(page).to have_button("Post", disabled: false)
  end

  it "sets visibility via the dropdown and posts it" do
    sign_in create(:user)
    visit new_hujah_path
    fill_in "hujah[body]", with: "A claim long enough to submit here"
    find('[data-composer-target="visLabel"]').click # open menu
    click_on "Private"
    click_on "Post"
    expect(Hujah.order(:created_at).last.visibility).to eq "private_only"
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Set suggested tags in the controller `new` action.**
```ruby
def new
  skip_authorization
  @parent = params[:slug] && Hujah.friendly.find(params[:slug])
  @hujah = Hujah.new
  @suggested_tags = Hashtag.order(hujahs_count: :desc).limit(6) # trending, for chips
end
```

- [ ] **Step 4: Rebuild `_compose_form`** to the mockup's "New hoojah" screen (asset lines ~10–65). Preserve these Rails bindings exactly:
  - `form_with model: @hujah, url: (…existing url…), local: true` wrapper, `data-controller="composer"` `data-composer-require-min-value="<%= @parent.nil? %>"`.
  - Textarea → `f.text_area :body`, `data-composer-target="body"`, `data-action="input->composer#input"`, placeholder "What's your hoojah?".
  - Post submit → `data-composer-target="post"`, disabled initial; label "Post".
  - **Top-level only:** the visibility control — a hidden `f.hidden_field :visibility, value: "visible_public", data: {composer_target: "visField"}` + a button (`data-composer-target="visLabel"` `data-action="composer#toggleMenu"`) + a menu (`data-composer-target="menu"` hidden) whose three items carry `data-action="composer#select"` `data-value="visible_public|followers_only|private_only"` `data-label="Public|Followers|Private"`. Reuse `ui/_menu` styling.
  - Suggested-hashtag chips: loop `@suggested_tags`, each a button `data-action="composer#addTag"` `data-tag="<%= tag.display %>"`; static empty state if none.
  - "How people will weigh in" preview: static markup (asset lines ~50–57).
  - Bottom bar: image button (visual-only), "Allow debates" toggle → `f.check_box :allow_debates` styled as the pill toggle (checked by default), "Draft" label.
  - **Reply mode (`@parent` present):** keep rendering `_parent_card` + `_stance_picker` in place of the visibility control (existing behavior), and set `data-composer-require-min-value="false"`.
  - `new.html.erb` stays a thin wrapper rendering `_compose_form`.

- [ ] **Step 5: Run system spec, expect PASS.** Also run the existing composer/reply request specs. Commit.
```bash
git add app/views/hujahs/_compose_form.html.erb app/views/hujahs/new.html.erb app/controllers/hujahs_controller.rb spec/system/composer_spec.rb
git commit -m "Rebuild the full-page hoojah composer to the 2026 design"
```

### Task 4.4: Inline feed composer

**Files:**
- Modify: `app/views/hujahs/index.html.erb` (add the inline composer at the top of the feed)
- Create: `app/views/hujahs/_inline_composer.html.erb`
- Test: `spec/system/feed_composer_spec.rb` (new, `js: true`)

- [ ] **Step 1: Failing system spec.**
```ruby
require "rails_helper"

RSpec.describe "Inline feed composer", :js do
  it "expands the pill and posts a hoojah" do
    sign_in create(:user)
    visit root_path
    find('[data-composer-target="collapsed"]').click
    fill_in "hujah[body]", with: "Inline composed claim about buses"
    within('[data-composer-target="expanded"]') { click_on "Post" }
    expect(page).to have_content("Inline composed claim about buses")
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Build `_inline_composer`** (asset: the `feedCollapsed`/`feedExpanded` blocks). A `data-controller="composer"` wrapper containing:
  - Collapsed pill (`data-composer-target="collapsed"` `data-action="click->composer#expand"`): avatar + "What's your hoojah?" + inert Post.
  - Expanded card (`data-composer-target="expanded"` hidden): `form_with model: Hujah.new, url: hujah_path… (POST /hoojah), local: true`, avatar + visibility pill (same bindings as 4.3), textarea (`data-composer-target="body"` `data-action="input->composer#input"`), "Min 8 characters to post" hint, Post (`data-composer-target="post"`), and a maximize button linking to `new_hujah_path`.
  - Render it at the top of `index.html.erb`'s feed column, only `if user_signed_in?`.
- [ ] **Step 4:** Ensure `POST /hoojah` returns Turbo that prepends the new card. If `HujahsController#create` currently only redirects, add `respond_to`: on `format.turbo_stream` prepend `hujahs/_hujah_card` to the feed stream target and reset the composer; keep the HTML redirect fallback. (Match the feed's existing stream target id in `index.html.erb`.)

- [ ] **Step 5: Run, expect PASS; commit.**
```bash
git add app/views/hujahs/index.html.erb app/views/hujahs/_inline_composer.html.erb app/controllers/hujahs_controller.rb app/views/hujahs/create.turbo_stream.erb spec/system/feed_composer_spec.rb
git commit -m "Add the inline feed composer"
```

---

## Track 5 — Surface 2: Single hujah argument

> Visual target: `docs/superpowers/specs/assets/hoojah-2026-single-hoojah.html`. Same rule: read current partial + mockup asset, rewrite markup, preserve the named Rails bindings.

### Task 5.1: Vote endpoint accepts conviction

**Files:**
- Modify: `app/controllers/votes_controller.rb`
- Test: `spec/requests/votes_spec.rb`

- [ ] **Step 1: Failing request spec.**
```ruby
it "records a conviction vote when conviction=1" do
  user = create(:user); sign_in user
  h = create(:hujah)
  post hujah_votes_path(h.slug), params: { vote: "1", conviction: "1" }
  expect(h.reload.conviction_count).to eq 1
  expect(h.votes.find_by(user: user).conviction).to be true
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Pass the flag through.**
```ruby
def create
  @hujah = Hujah.friendly.find(params[:slug])
  authorize @hujah, :vote?
  @hujah.cast_vote(by: current_user, choice: params[:vote], conviction: params[:conviction] == "1")

  respond_to do |format|
    format.turbo_stream
    format.html { redirect_to hujah_path(@hujah.slug) }
  end
end
```

- [ ] **Step 4: Run, expect PASS; commit.**
```bash
git add app/controllers/votes_controller.rb spec/requests/votes_spec.rb
git commit -m "Accept a conviction flag on the vote endpoint"
```

### Task 5.2: `conviction_controller` (hold-to-charge)

**Files:**
- Create: `app/javascript/controllers/conviction_controller.js`
- Test: exercised by 5.4 system spec.

- [ ] **Step 1: Implement.** Tap = normal vote; hold past `duration` = conviction vote. Submits through the existing `button_to` forms by setting a hidden `conviction` field and requesting submit, so the Turbo Stream vote-bars replacement still runs.
```javascript
import { Controller } from "@hotwired/stimulus"

// Progressive enhancement over the plain button_to vote forms. Pointer-down starts a
// charge timer + ring; release before threshold submits a NORMAL vote (tap); holding
// to completion submits with conviction=1 (locked forever). With JS off, the buttons
// are ordinary submit buttons casting a normal vote.
export default class extends Controller {
  static targets = ["ring", "overlay", "convictionField"]
  static values = { duration: { type: Number, default: 900 }, locked: Boolean }

  start(event) {
    if (this.lockedValue) return
    this.form = event.currentTarget.closest("form")
    this.held = false
    this.t0 = performance.now()
    this.raf = requestAnimationFrame(this.tick.bind(this))
    this.timer = setTimeout(() => { this.held = true; this.commit(true) }, this.durationValue)
    if (this.hasOverlayTarget) this.overlayTarget.hidden = false
  }

  tick(now) {
    const pct = Math.min(1, (now - this.t0) / this.durationValue)
    if (this.hasRingTarget) this.ringTarget.style.setProperty("--charge", pct)
    if (pct < 1 && !this.held) this.raf = requestAnimationFrame(this.tick.bind(this))
  }

  end() {
    if (this.held) return // conviction already committed by the timer
    this.cancelCharge()
    this.commit(false) // quick tap → normal vote
  }

  leave() { if (!this.held) this.cancelCharge() } // pointer left the button → cancel, no vote

  cancelCharge() {
    clearTimeout(this.timer); cancelAnimationFrame(this.raf)
    if (this.hasOverlayTarget) this.overlayTarget.hidden = true
    if (this.hasRingTarget) this.ringTarget.style.setProperty("--charge", 0)
  }

  noMenu(event) { event.preventDefault() } // suppress the long-press context menu

  commit(conviction) {
    clearTimeout(this.timer); cancelAnimationFrame(this.raf)
    if (!this.form) return
    // Per-form hidden field (there are three forms under one controller — one per
    // stance — so look it up INSIDE this.form, not via a controller target).
    const field = this.form.querySelector('input[name="conviction"]')
    if (field) field.value = conviction ? "1" : ""
    this.form.requestSubmit()
  }
}
```
> There is ONE controller on the vote-hero wrapper and THREE `<form>`s inside it (one per stance). Each form is an explicit `form_with url: hujah_votes_path(hujah.slug)` carrying `hidden_field_tag :vote, N`, `hidden_field_tag :conviction, ""`, and a submit button with `data-action="pointerdown->conviction#start pointerup->conviction#end pointerleave->conviction#leave contextmenu->conviction#noMenu"` + `data-stance` + (for the overlay color) `data-charge-color`. The wrapper is `data-controller="conviction"` `data-conviction-locked-value="<%= current_vote_locked %>"` and holds the shared `ring`/`overlay` targets.

- [ ] **Step 2: Commit.**
```bash
git add app/javascript/controllers/conviction_controller.js
git commit -m "Add conviction_controller for hold-to-charge voting"
```

### Task 5.3: Build the vote hero (new partial — do NOT touch the shared `_vote_bars`)

> **Why a new partial:** `_vote_bars` is rendered by the FEED card (`_hujah_card`) too. The tall 104px hero belongs only on the single-hujah page. Leave `_vote_bars` as-is (it retints automatically via the Track 1 tokens) and add `_vote_hero` for the show page. The vote Turbo Stream will target whichever widget exists on the page.

**Files:**
- Create: `app/views/hujahs/_vote_hero.html.erb`
- Modify: `app/views/hujahs/show.html.erb` (render `_vote_hero` instead of `_vote_bars`), `app/views/votes/create.turbo_stream.erb`
- Test: `spec/system/vote_hero_spec.rb` (new, `js: true`) + existing votes request spec

- [ ] **Step 1: Failing system spec** (tap casts normal vote; hold casts conviction).
```ruby
require "rails_helper"

RSpec.describe "Vote hero", :js do
  it "tap casts a normal vote; hold casts a conviction vote" do
    sign_in create(:user)
    h = create(:hujah)
    visit hujah_path(h.slug)
    find('[data-stance="agree"]').click # tap
    expect(h.reload.agree_count).to eq 1
    expect(h.conviction_count).to eq 0
    # hold-to-charge covered by a targeted driver action; see helper `hold(selector, 1.0)`
  end
end
```
> Add a small Cuprite helper `hold(selector, seconds)` doing pointer down → sleep → up if one doesn't exist.

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Build `_vote_hero`** to the vote-hero card (asset lines ~32–104). Locals: `hujah`, `current_user_vote`, `current_vote_locked`. Structure:
  - Wrapper `id="<%= dom_id(hujah, :vote_hero) %>"` `data-controller="conviction"` `data-conviction-locked-value="<%= current_vote_locked %>"`.
  - "Where do you stand?" label + aggregate conviction badge (`hujah.conviction_count`).
  - Three tall (~104px) stance targets. Each is an explicit `<%= form_with url: hujah_votes_path(hujah.slug), method: :post do |f| %>` containing `hidden_field_tag :vote, N`, `hidden_field_tag :conviction, ""`, and a submit `<button>` carrying `data-stance="agree|neutral|disagree"`, `data-charge-color` (the stance var), the pointer `data-action`s (start/end/leave/noMenu), and the current-vote inversion (solid `bg-<stance>` + white glyph when `current_user_vote == stance`). Below each: `<pct>%` + count.
  - Combined results bar (agree/neutral/disagree widths), and the charge overlay (`data-conviction-target="overlay"` hidden, with a `ring` element `data-conviction-target="ring"` driven by `--charge`) + boom markup (asset lines ~106–137). Port keyframes are already in the bundle (Task 1.1).
  - Use `bg-agree`/`text-neutral`/`bg-card`/`text-ink`/etc. utilities — never raw hex, never interpolate a NEW prefix without safelisting it.
  - No-JS fallback: each form is a real POST that casts a normal vote (conviction blank) — fully works without the controller.

- [ ] **Step 4: Render it on the show page.** In `show.html.erb`, replace the `render "hujahs/vote_bars", …` call inside the claim card with:
```erb
<%= render "hujahs/vote_hero",
      hujah: @hujah,
      current_user_vote: @hujah.current_user_vote(logged_in: user_signed_in?, current_user_id: current_user&.id),
      current_vote_locked: (user_signed_in? && @hujah.votes.find_by(user_id: current_user.id)&.conviction) || false %>
```

- [ ] **Step 5: Update the vote Turbo Stream to target whichever widget exists.** `votes/create.turbo_stream.erb` — replace BOTH ids (an absent target is a no-op, so the feed still updates `_vote_bars` and the show page updates `_vote_hero`):
```erb
<%= turbo_stream.replace dom_id(@hujah, :vote_bars) do %>
  <%= render "hujahs/vote_bars", hujah: @hujah,
        current_user_vote: @hujah.current_user_vote(logged_in: true, current_user_id: current_user.id) %>
<% end %>
<%= turbo_stream.replace dom_id(@hujah, :vote_hero) do %>
  <%= render "hujahs/vote_hero", hujah: @hujah,
        current_user_vote: @hujah.current_user_vote(logged_in: true, current_user_id: current_user.id),
        current_vote_locked: (@hujah.votes.find_by(user_id: current_user.id)&.conviction) || false %>
<% end %>
```
> The argument-composer unlock-on-vote replace is added in Task 5.6 Step 4 (a third `turbo_stream.replace` for the composer bar).

- [ ] **Step 6: Run system + request specs, expect PASS; commit.**
```bash
git add app/views/hujahs/_vote_hero.html.erb app/views/hujahs/show.html.erb app/views/votes/create.turbo_stream.erb spec/system/vote_hero_spec.rb
git commit -m "Add the vote hero with hold-to-charge conviction"
```

### Task 5.4: Header, author/claim hero, hashtag chips

> Build the hero as NEW markup in `show.html.erb` (or a new `_claim_hero` partial). Do NOT modify the shared `_hujah_header` — it is rendered by every feed card and restyling it would change the out-of-scope feed. The show page will stop rendering the claim inside `ui/card` + `_hujah_header` and use the 2026 hero instead.

**Files:**
- Modify: `app/views/hujahs/show.html.erb`
- Create (optional): `app/views/hujahs/_claim_hero.html.erb`
- Test: `spec/system/single_hujah_spec.rb` (new, `js: true`)

- [ ] **Step 1: Failing spec** — the show page renders the claim, a `#tag` chip linking to `tag_path`, and (if present) the Follow button; header shows "Trending in #… · N votes" or "Hoojah".
```ruby
it "renders the claim hero with a tag chip linking to the tag feed" do
  h = create(:hujah, body: "Free transit in every #KlangValley city please now")
  visit hujah_path(h.slug)
  expect(page).to have_link("#KlangValley", href: tag_path("klangvalley"))
end
```

- [ ] **Step 2–4:** Build the contextual header (back / center label "Trending in #Tag · N votes" or "Hoojah" / share / more — reuse the existing `_share_menu` + `more`/`flag` dialog markup currently in `show.html.erb`) and the author+claim hero (asset lines ~9–30): 46px avatar (`ui/avatar` size `:md` or inline), name, `@handle · date` (compact `%b %-d`), Follow button (reuse the existing follow control if one exists in `users/`; else omit for now — flag in HANDOVER), claim via `format_body(@hujah.body)` at hero size, hashtag chips from `@hujah.hashtags` linking `tag_path(tag.name)`. **Omit the verified tick** (no `verified?` on User). Keep the existing more-actions/flag `ui/menu` block. Run, expect PASS. Commit.
```bash
git add app/views/hujahs/show.html.erb app/views/hujahs/_claim_hero.html.erb spec/system/single_hujah_spec.rb
git commit -m "Rebuild the single-hoojah header and claim hero"
```

### Task 5.5: Debates section + responses restyle

**Files:**
- Modify: `app/views/hujahs/show.html.erb` (debates section), `app/views/hujahs/_child_card.html.erb`, `app/views/hujahs/_response_filter.html.erb`, `app/views/hujahs/_challenge_dialog.html.erb`
- Test: `spec/system/single_hujah_spec.rb`

- [ ] **Step 1: Failing spec** — the response filter still filters by stance; the Challenge affordance is hidden when `!allow_debates?`.
```ruby
it "hides Challenge when the claim disallows debates" do
  claim = create(:hujah, allow_debates: false)
  replier = create(:user); claim.cast_vote(by: replier, choice: 3)
  create(:hujah, parent: claim, user: replier, vote: 3, body: "Counterpoint here friend")
  sign_in create(:user)
  visit hujah_path(claim.slug)
  expect(page).not_to have_text("Challenge")
end
```

- [ ] **Step 2–4:** Restyle the debates list (`_debate_card` usage — Live pill w/ breathing dot, concluded rows, "See all N concluded") and `_child_card` (6px stance-left-border, avatar, body, counts). Keep the `response_filter_controller` contract intact on each card: `data-response-filter-target="item"` + `data-response-filter-vote="<stance>"` (and the tabs' `data-response-filter-filter-param` + `data-action` calling `response-filter#filter`). `_child_card` already receives both `child` and `hujah` locals — gate the Challenge affordance with `if user_signed_in? && current_user.id != child.user_id && hujah.allow_debates?` (add the `hujah.allow_debates?` clause to the existing guard). Show an "In debate" badge when the response already has a live debate. Run, expect PASS. Commit.
```bash
git add app/views/hujahs/_child_card.html.erb app/views/hujahs/_response_filter.html.erb app/views/hujahs/_challenge_dialog.html.erb app/views/hujahs/show.html.erb spec/system/single_hujah_spec.rb
git commit -m "Restyle debates list and responses to the 2026 design"
```

### Task 5.6: Argument composer bar + respond overlay

**Files:**
- Create: `app/javascript/controllers/argument_composer_controller.js`, `app/views/hujahs/_argument_composer.html.erb`
- Modify: `app/views/hujahs/show.html.erb` (replace the "Add hoojah" button with the sticky composer bar)
- Test: `spec/system/argument_composer_spec.rb` (new, `js: true`), `spec/requests/hujahs_spec.rb`

- [ ] **Step 1: Failing specs.**
```ruby
# system
it "is locked until the viewer votes, then lets them post an argument" do
  h = create(:hujah); user = create(:user); sign_in user
  visit hujah_path(h.slug)
  expect(page).to have_text("Vote to join the argument")
  find('[data-stance="agree"]').click # vote via the hero
  # composer unlocks (Turbo re-render of the bar or client sync)
  find('[data-argument-composer-target="pill"]').click
  fill_in "hujah[body]", with: "Because fewer cars cleaner air"
  within('[data-argument-composer-target="expanded"]') { click_on "Send" }
  expect(page).to have_content("Because fewer cars cleaner air")
end

# request: reply blocked before voting (policy from Task 2.6)
it "rejects a reply before voting" do
  h = create(:hujah); sign_in create(:user)
  post "/hoojah", params: { hujah: { body: "no vote yet reply", parent_id: h.id, vote: "1" } }
  expect(response).to have_http_status(:forbidden).or have_http_status(:found) # Pundit redirect
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: `argument_composer_controller`** — three states (`locked`/`collapsed`/`expanded`), stance selection, send-enable, and opening the full-screen respond overlay.
```javascript
import { Controller } from "@hotwired/stimulus"

// The sticky argument bar on a single hoojah. States: locked (must vote first),
// collapsed (pill + mini stance), expanded (stance row + textarea). `voted` is set
// server-side; if the viewer votes inline we also unlock optimistically.
export default class extends Controller {
  static targets = ["locked", "collapsed", "expanded", "pill", "body", "send", "stanceField"]
  static values = { voted: Boolean }

  connect() { this.render() }
  unlock() { this.votedValue = true; this.render() }        // called after an inline vote
  expand() { this.state = "expanded"; this.render(); this.bodyTarget?.focus() }
  collapse() { this.state = "collapsed"; this.render() }

  pickStance(event) {
    this.stanceFieldTarget.value = event.currentTarget.dataset.value
    this.expand()
  }

  input() {
    const ok = this.bodyTarget.value.trim().length > 0 && this.stanceFieldTarget.value
    if (this.hasSendTarget) this.sendTarget.disabled = !ok
  }

  render() {
    const locked = !this.votedValue
    this.lockedTarget.hidden = !locked
    const state = this.state || "collapsed"
    if (this.hasCollapsedTarget) this.collapsedTarget.hidden = locked || state !== "collapsed"
    if (this.hasExpandedTarget) this.expandedTarget.hidden = locked || state !== "expanded"
  }
}
```

- [ ] **Step 4: Build `_argument_composer`** (asset: ARGUMENT composer bar + respond overlay). Wrapper `data-controller="argument-composer"` `data-argument-composer-voted-value="<%= @hujah.voted_by?(current_user) %>"`. The expanded state is a `form_with model: Hujah.new, url: hujah_path?…` → actually **POST /hoojah** with hidden `parent_id=@hujah.id`, `vote` (`data-argument-composer-target="stanceField"`, defaulting to the viewer's current stance), and `body` (`data-argument-composer-target="body"`). Locked state shows "Vote to join the argument" + 3 mini stance buttons that scroll to / trigger the hero vote. The maximize button reveals the respond overlay (asset "Respond with a stance"): parent-claim quote, big stance picker, large textarea, "Posting as {stance}". Wire the hero's vote success to call `argument-composer#unlock` (e.g. the vote Turbo Stream also re-renders the composer bar's `voted` value — simplest: `votes/create.turbo_stream.erb` also replaces the composer bar partial with `voted: true`). Replace the old "Add hoojah" `link_to respond_hujah_path` with this bar, keeping `respond_hujah_path` as the no-JS fallback link inside the locked/collapsed state.

- [ ] **Step 5: Run specs, expect PASS; commit.**
```bash
git add app/javascript/controllers/argument_composer_controller.js app/views/hujahs/_argument_composer.html.erb app/views/hujahs/show.html.erb app/views/votes/create.turbo_stream.erb spec/system/argument_composer_spec.rb spec/requests/hujahs_spec.rb
git commit -m "Add the argument composer bar and respond overlay"
```

---

## Final integration

### Task 6.1: Full green + review

- [ ] **Step 1: Run the full gate.**
```bash
bin/ci
```
Expected: all gates + specs green. Fix any regressions (existing specs that assumed the old composer/vote markup, all-public claims, or reply-without-vote).

- [ ] **Step 2: Prosopite check.** `grep -c 'N+1 queries detected' log/prosopite.log` after a run — must not exceed the Slice-10 baseline (146) by more than the new surfaces warrant; add `includes` for any new N+1 (e.g. `@hujah.hashtags`, `@children` challenge lookups).

- [ ] **Step 3: Independent code review** (superpowers:requesting-code-review) across all tracks, then batched fixes, then re-run `bin/ci`.

- [ ] **Step 4: Update `docs/superpowers/HANDOVER.md`** with the redesign status and any deferred items (design-system re-mirror, scheme picker UI surface, image-attach wiring). Commit.

---

## Self-review notes (author)

- **Spec coverage:** §2 theming → Track 1; §3 data model → Track 2 (2.1–2.5) + Track 3; §4 routes → 3.3 + 5.1; §5 new post → Track 4; §6 single hujah → Track 5; §7 testing → per-task specs + 6.1; §8 tracks → this structure. All covered.
- **Open items (spec §9) resolved here:** hashtag canonicalization = lower-cased `name` + `display` cache (3.1); verified tick = omitted (5.4); image button = visual-only (4.3); scheme switcher = navbar cycle button (1.3).
- **Consistency:** `voted_by?` (2.3) used by policy (2.6) and composer (5.6); `conviction`/`conviction_count` names consistent across 2.1/2.2/2.4/5.x; `dom_id(hujah, :vote_bars)` preserved (5.3) so the existing Turbo Stream still targets it.
- **Deferred/verify during execution:** exact factory traits (accepted follow, debate), the feed Turbo-Stream target id, whether `HujahsController#create` already has a Turbo path, and `format_body`'s current escaping — each task says "read the current file first".

