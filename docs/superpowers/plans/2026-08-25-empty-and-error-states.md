# Empty-state & Error-journey Coverage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every empty-collection, degenerate ("why empty"), and error-journey gap found in the user-journey audit, using one systematized approach.

**Architecture:** Extend the single `ui/_empty_state` primitive with an optional CTA slot (all existing call sites stay byte-identical), route every empty/zero-result surface through it, and add a real `ErrorsController` with branded 404/422/500 wired through `config.exceptions_app = routes`. Client-side stance-filter emptiness is handled in the existing Stimulus controller.

**Tech Stack:** Rails 8.1, Hotwire (Turbo + Stimulus over importmap), Tailwind v4, RSpec + FactoryBot + Cuprite (headless Chrome for `js: true` system specs), Pundit.

**Reference:** Design spec at `docs/superpowers/specs/2026-08-25-empty-and-error-states-design.md`.

**Conventions to honor (from CLAUDE.md):**
- StandardRB formats Ruby. No Claude/Anthropic branding in commits. Subjects: plain imperative.
- Tailwind: ERB is scanned as source, so any concrete class in ERB compiles a rule. Interpolated classes need `@source inline(...)`. This plan uses only classes already in the bundle plus a few common utilities emitted directly from the ERB it edits.
- Run one RSpec suite at a time (shared Postgres test DB).
- Test commands: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec <path>` (append `--exclude-pattern "spec/system/**/*"` for the fast loop).

---

## File Structure

**Create:**
- `app/controllers/errors_controller.rb` — maps an error status to a branded page.
- `app/views/errors/show.html.erb` — the branded 404/422/500 body.
- `app/helpers/notifications_helper.rb` — reason-aware empty message for notifications.
- Spec files listed per task.

**Modify:**
- `app/views/ui/_empty_state.html.erb` — additive CTA slot.
- `app/views/hujahs/index.html.erb` — global feed empty states + reworded Following copy.
- `app/views/tags/show.html.erb` + `app/controllers/tags_controller.rb` — empty state + visible count.
- `app/javascript/controllers/response_filter_controller.js` + `app/views/hujahs/_response_filter.html.erb` — filtered-empty placeholder; grammar fix.
- `app/views/notifications/index.html.erb` + `app/views/notifications/read_all.turbo_stream.erb` — reason-aware copy.
- `app/views/search/_results.html.erb` — zero-results via primitive; empty hashtag cloud.
- `app/views/users/show.html.erb` — debates glyph, owner CTA.
- `config/routes.rb` + `config/environments/production.rb` — error routes + exceptions_app.
- `app/controllers/hujahs_controller.rb` + `app/controllers/tags_controller.rb` — stop swallowing `RecordNotFound` into a blank body.
- `public/404.html`, `public/422.html`, `public/500.html` — rebrand.

---

## Task 1: Extend `ui/_empty_state` with an optional CTA slot

**Files:**
- Modify: `app/views/ui/_empty_state.html.erb`
- Test: `spec/views/ui/empty_state_spec.rb` (create)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/views/ui/empty_state_spec.rb
require "rails_helper"

RSpec.describe "ui/_empty_state", type: :view do
  it "renders just the sentence and glyph with no CTA by default" do
    render "ui/empty_state", message: "Nothing here"
    expect(rendered).to have_text("Nothing here")
    expect(rendered).not_to have_selector("a")
  end

  it "renders a single pill CTA when cta_label and cta_href are both present" do
    render "ui/empty_state", message: "No hoojahs yet",
      cta_label: "Post the first hoojah", cta_href: "/hoojah/new"
    expect(rendered).to have_link("Post the first hoojah", href: "/hoojah/new")
  end

  it "renders no CTA when only cta_label is given (href missing)" do
    render "ui/empty_state", message: "No hoojahs yet", cta_label: "Post"
    expect(rendered).not_to have_selector("a")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/views/ui/empty_state_spec.rb`
Expected: FAIL — the CTA example finds no `<a>`.

- [ ] **Step 3: Record the Tailwind bundle baseline (positive-control discipline)**

Run: `bin/rails tailwindcss:build >/dev/null 2>&1 && md5 -q app/assets/builds/tailwind.css` (or `md5sum` on Linux). Note the hash — after Step 4 it may legitimately move (new `flex-col`/`p-6`/`gap-3` utilities from real ERB), which is expected for a code edit, not a comment edit.

- [ ] **Step 4: Implement the additive CTA slot**

Replace the final render block (the single `<div>`) in `app/views/ui/_empty_state.html.erb`. Keep the existing header comment and the locals block (`message`/`icon`/`tone`/`align`) intact; append the CTA locals and branch:

```erb
<% message = local_assigns.fetch(:message)
   icon = local_assigns.fetch(:icon, "message-circle")
   tone = (local_assigns[:tone]&.to_sym == :muted) ? "text-grey" : "text-light-grey"
   align = (local_assigns[:align]&.to_sym == :center) ? "justify-center" : "justify-start"
   cta_label = local_assigns[:cta_label]
   cta_href = local_assigns[:cta_href]
   has_cta = cta_label.present? && cta_href.present? %>
<% if has_cta %>
  <div class="flex flex-col items-center gap-3 text-sm p-6 bg-white <%= tone %> <%= local_assigns[:class] %>">
    <div class="flex items-center gap-1 justify-center">
      <%= lucide_icon(icon, class: "w-4 h-4") if icon.present? %>
      <span><%= message %></span>
    </div>
    <%= link_to cta_label, cta_href, class: ds_button_classes(tone: "primary", size: :sm) %>
  </div>
<% else %>
  <div class="flex items-center gap-1 text-sm p-3 bg-white <%= tone %> <%= align %> <%= local_assigns[:class] %>">
    <%= lucide_icon(icon, class: "w-4 h-4") if icon.present? %>
    <span><%= message %></span>
  </div>
<% end %>
```

Note: `ds_button_classes` default `variant: :outline` IS the house pill style ("2px coloured border"). Do not pass a `variant:` value you have not confirmed exists in `DesignSystemHelper::VARIANTS`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/views/ui/empty_state_spec.rb`
Expected: PASS (all three).

- [ ] **Step 6: Verify the 9 existing call sites are byte-identical for the no-CTA path**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests --exclude-pattern "spec/system/**/*"`
Expected: PASS — no regression (no existing caller passes `cta_*`, so they hit the `else` branch which is identical markup to before).

- [ ] **Step 7: Commit**

```bash
git add app/views/ui/_empty_state.html.erb spec/views/ui/empty_state_spec.rb
git commit -m "Add optional CTA slot to ui/_empty_state primitive"
```

---

## Task 2: Global feed empty state (HIGH)

**Files:**
- Modify: `app/views/hujahs/index.html.erb`
- Test: `spec/requests/feed_empty_state_spec.rb` (create)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/feed_empty_state_spec.rb
require "rails_helper"

RSpec.describe "Feed empty states", type: :request do
  it "prompts an anonymous visitor to sign up when there are no hoojahs" do
    get root_path
    expect(response.body).to include("No hoojahs yet")
    expect(response.body).to include(new_user_registration_path)
  end

  it "prompts a signed-in user to post the first hoojah when the feed is empty" do
    user = create(:user)
    sign_in user
    get root_path
    expect(response.body).to include("No hoojahs yet")
    expect(response.body).to include(new_hujah_path)
  end

  it "shows the reworded Following-empty copy without misdirection" do
    user = create(:user)
    sign_in user
    get root_path(filter: "following")
    expect(response.body).to include("When people you follow post")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/feed_empty_state_spec.rb`
Expected: FAIL — "No hoojahs yet" not present; old Following copy still there.

- [ ] **Step 3: Implement the empty branches**

In `app/views/hujahs/index.html.erb`, replace the existing Following-only empty block (the `<% if params[:filter] == "following" ... %> ... <% end %>` at lines ~23-27) with a single empty dispatcher placed in the same spot (before `<div id="hujah-feed">`):

```erb
    <%# Empty states. Following stays a centred two-clause paragraph (documented above);
        the global/default feed gets the design-system primitive with a key-funnel CTA. %>
    <% if @hujahs.empty? %>
      <% if params[:filter] == "following" && user_signed_in? %>
        <p class="text-center text-grey py-8">
          When people you follow post, you'll see it here.
        </p>
      <% elsif user_signed_in? %>
        <%= render "ui/empty_state", message: "No hoojahs yet", align: :center,
              cta_label: "Post the first hoojah", cta_href: new_hujah_path %>
      <% else %>
        <%= render "ui/empty_state",
              message: "No hoojahs yet — sign up to start the conversation", align: :center,
              cta_label: "Sign up", cta_href: new_user_registration_path %>
      <% end %>
    <% end %>
```

Keep the surrounding comment block (lines 17-22) — it still explains why Following is a paragraph.

- [ ] **Step 4: Run tests to verify they pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/feed_empty_state_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/hujahs/index.html.erb spec/requests/feed_empty_state_spec.rb
git commit -m "Add global-feed empty states with key-funnel CTA; reword Following-empty"
```

---

## Task 3: Tag page empty state + visible-count fix (HIGH)

**Files:**
- Modify: `app/controllers/tags_controller.rb`, `app/views/tags/show.html.erb`
- Test: `spec/requests/tags_spec.rb` (create or extend)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/tags_spec.rb
require "rails_helper"

RSpec.describe "Tag page empty state", type: :request do
  it "shows an empty state when a tag has no visible hoojahs" do
    tag = create(:hashtag) # a hashtag with zero associated visible hoojahs
    get tag_path(tag.name)
    expect(response.body).to include("No hoojahs tagged")
    expect(response.body).to have_http_status(:ok)
  end
end
```

Note: confirm a `:hashtag` factory exists (`ls spec/factories | grep hashtag`). If not, add one that sets `name`/`display` to a canonical value; `Hashtag.canonical` lowercases.

- [ ] **Step 2: Run test to verify it fails**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/tags_spec.rb`
Expected: FAIL — body has no "No hoojahs tagged".

- [ ] **Step 3: Add a visible count in the controller**

In `app/controllers/tags_controller.rb#show`, after building `base` and before `pagy`, add:

```ruby
    @count = base.count
    @pagy, @hujahs = pagy(:countless, base)
```

- [ ] **Step 4: Use the visible count + add the empty branch in the view**

In `app/views/tags/show.html.erb`, change the header count line from `@tag.hujahs_count` to `@count`:

```erb
      <p class="text-ink-2 text-sm mt-2">
        <%= pluralize(@count, "hoojah") %> tagged
      </p>
```

Then replace the `<div id="hujah-feed">` block with an empty-aware version:

```erb
    <% if @hujahs.any? %>
      <div id="hujah-feed">
        <%= render partial: "hujahs/hujah_card", collection: @hujahs, as: :hujah %>
      </div>
    <% else %>
      <div id="hujah-feed">
        <%= render "ui/empty_state", message: "No hoojahs tagged ##{@tag.display} yet", icon: "hash" %>
      </div>
    <% end %>
```

Keep `#hujah-feed` present in both branches so the load-more turbo stream target is stable.

- [ ] **Step 5: Run tests to verify they pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/tags_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/tags_controller.rb app/views/tags/show.html.erb spec/requests/tags_spec.rb
git commit -m "Add tag-page empty state and use visible count in header"
```

---

## Task 4: Response stance-filter empty placeholder (HIGH) — Stimulus

> **Dispatch this task to the `better-stimulus` agent.** It touches `response_filter_controller.js`, whose data-attribute API is FROZEN (documented in `_response_filter.html.erb:6-16`). Do not rename any existing target/param.

**Files:**
- Modify: `app/javascript/controllers/response_filter_controller.js`, `app/views/hujahs/_response_filter.html.erb`
- Test: `spec/system/response_filter_empty_spec.rb` (create, `js: true`)

- [ ] **Step 1: Write the failing system test**

```ruby
# spec/system/response_filter_empty_spec.rb
require "rails_helper"

RSpec.describe "Response filter empty state", type: :system, js: true do
  it "shows a placeholder when a stance filter matches no responses" do
    author = create(:user)
    hujah = create(:hujah, user: author)
    responder = create(:user)
    # One agreeing response only.
    create(:hujah, parent: hujah, user: responder, stance: "agree")

    sign_in author
    visit hujah_path(hujah.slug)
    click_button "Disagree"

    expect(page).to have_text("No responses match this filter yet")
  end
end
```

Note: confirm the reply factory shape (a child `Hujah` with `parent:` and `stance:`). Adjust the factory call to match `spec/factories/hujahs.rb` (a response may be created via a trait). Read that factory first.

- [ ] **Step 2: Run test to verify it fails**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/response_filter_empty_spec.rb`
Expected: FAIL — placeholder text never appears (cards just hide into a void).

- [ ] **Step 3: Add the placeholder element to the view**

In `app/views/hujahs/_response_filter.html.erb`, inside the `<div id="<%= dom_id(hujah, :responses) %>" ...>` container, in the `<% if children.any? %>` branch, after the `children.each` loop and before the branch closes, add an initially-hidden placeholder:

```erb
      <div data-response-filter-target="empty" hidden>
        <%= render "ui/empty_state", message: "No responses match this filter yet", class: "px-4" %>
      </div>
```

(It lives in the `children.any?` branch only — when there are zero responses total, the existing `responses_empty` server state covers it.)

- [ ] **Step 4: Add the `empty` target + count logic to the controller**

In `app/javascript/controllers/response_filter_controller.js`, add `"empty"` to `static targets` and update `activeValueChanged`:

```js
export default class extends Controller {
  static targets = ["tab", "item", "empty"]
  static values = { active: { type: String, default: "all" } }

  filter(event) {
    this.activeValue = event.params.filter
  }

  activeValueChanged(value) {
    let visible = 0
    this.itemTargets.forEach((el) => {
      const show = value === "all" || el.dataset.responseFilterVote === value
      el.toggleAttribute("hidden", !show)
      if (show) visible += 1
    })
    if (this.hasEmptyTarget) {
      // Only when responses exist but none match the current filter — never when
      // there are simply no responses at all (the server renders that state).
      this.emptyTarget.toggleAttribute("hidden", !(visible === 0 && this.itemTargets.length > 0))
    }
    this.tabTargets.forEach((tab) => {
      tab.setAttribute(
        "aria-pressed",
        String(tab.dataset.responseFilterFilterParam === value)
      )
    })
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/response_filter_empty_spec.rb`
Expected: PASS.

- [ ] **Step 6: Fix the grammar drift on the total-empty state (LOW polish, same file)**

In the same `_response_filter.html.erb`, change `message: "No response yet"` to `message: "No responses yet"` (matches the plural used everywhere else).

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/response_filter_controller.js app/views/hujahs/_response_filter.html.erb spec/system/response_filter_empty_spec.rb
git commit -m "Show placeholder when a response stance filter matches nothing"
```

---

## Task 5: Notifications reason-aware empty copy (MEDIUM)

**Files:**
- Create: `app/helpers/notifications_helper.rb`
- Modify: `app/views/notifications/index.html.erb`, `app/views/notifications/read_all.turbo_stream.erb`
- Test: `spec/requests/notifications_empty_spec.rb` (create)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/notifications_empty_spec.rb
require "rails_helper"

RSpec.describe "Notifications filtered-empty copy", type: :request do
  it "says no mentions when the Mentions filter is empty" do
    user = create(:user)
    sign_in user
    get notifications_path(filter: "mentions")
    expect(response.body).to include("No mentions yet")
  end

  it "says no debate activity when the Debates filter is empty" do
    user = create(:user)
    sign_in user
    get notifications_path(filter: "debates")
    expect(response.body).to include("No debate activity yet")
  end

  it "says you have no notifications on the unfiltered empty list" do
    user = create(:user)
    sign_in user
    get notifications_path
    expect(response.body).to include("You have no notifications")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/notifications_empty_spec.rb`
Expected: FAIL — all three currently render "You have no notifications".

- [ ] **Step 3: Add the helper**

```ruby
# app/helpers/notifications_helper.rb
module NotificationsHelper
  # Reason-aware empty message for the notifications list. Keyed on the same filter
  # key NotificationsController#index computes ("all" | "mentions" | "debates").
  def notifications_empty_message(filter)
    case filter
    when "mentions" then "No mentions yet"
    when "debates" then "No debate activity yet"
    else "You have no notifications"
    end
  end
end
```

- [ ] **Step 4: Use it in both render paths**

In `app/views/notifications/index.html.erb`, change the empty branch to:

```erb
    <% if @notifications.empty? %>
      <%= render "ui/empty_state", message: notifications_empty_message(@filter), icon: "bell" %>
    <% end %>
```

In `app/views/notifications/read_all.turbo_stream.erb`, make the identical change to its empty branch. (`@filter` is set by both `index` and `read_all`? `read_all` does not set `@filter` — it always re-renders the full unfiltered list, so pass `"all"` explicitly there:)

```erb
    <% if @notifications.empty? %>
      <%= render "ui/empty_state", message: notifications_empty_message("all"), icon: "bell" %>
    <% end %>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/notifications_empty_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/helpers/notifications_helper.rb app/views/notifications/index.html.erb app/views/notifications/read_all.turbo_stream.erb spec/requests/notifications_empty_spec.rb
git commit -m "Make notifications empty copy reason-aware per filter"
```

---

## Task 6: Search zero-results + empty hashtag cloud via primitive (MEDIUM)

**Files:**
- Modify: `app/views/search/_results.html.erb`
- Test: `spec/requests/search_empty_spec.rb` (create)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/search_empty_spec.rb
require "rails_helper"

RSpec.describe "Search empty states", type: :request do
  it "renders the design-system empty state for a zero-result query" do
    get search_path(q: "zzz-nothing-matches-zzz")
    expect(response.body).to include("No results for")
    # the primitive's glyph markers (svg from lucide) are present
    expect(response.body).to have_selector("svg")
  end

  it "renders an empty state when there are no hashtags to browse" do
    get search_path
    expect(response.body).to include("No hashtags yet")
  end
end
```

Note: the second example assumes a fresh DB has no hashtags; the suite is transactional so it holds. Confirm `search_path` accepts `q` (the controller reads `params[:q]`/`@query` — check `SearchController#index`).

- [ ] **Step 2: Run test to verify it fails**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/search_empty_spec.rb`
Expected: FAIL — zero-results is a bare `<p>` (no svg), and empty cloud shows bare headers.

- [ ] **Step 3: Route zero-results through the primitive**

In `app/views/search/_results.html.erb`, replace the `<% else %>` bare paragraph (line ~22-24) with:

```erb
  <% else %>
    <%= render "ui/empty_state", message: "No results for “#{@query}”.", icon: "search" %>
  <% end %>
```

- [ ] **Step 4: Give the empty hashtag cloud its own state**

Still in `_results.html.erb`, wrap the two hashtag sections (the "Trending hashtags" + "Browse hashtags" blocks, lines ~28-33) so they collapse to one empty state when there are no hashtags:

```erb
<% browse_hashtags = @browse_hashtags.to_a %>
<% if browse_hashtags.any? %>
  <div class="text-xs font-bold uppercase tracking-wide text-faint mt-1 mb-2">Trending hashtags</div>
  <%= render "search/hashtag_chips", hashtags: browse_hashtags.first(8) %>

  <div class="text-xs font-bold uppercase tracking-wide text-faint mt-4 mb-2">Browse hashtags</div>
  <%= render "search/hashtag_chips", hashtags: browse_hashtags %>
<% else %>
  <%= render "ui/empty_state", message: "No hashtags yet", icon: "hash" %>
<% end %>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/search_empty_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/search/_results.html.erb spec/requests/search_empty_spec.rb
git commit -m "Route search zero-results and empty hashtag cloud through ui/_empty_state"
```

---

## Task 7: Profile Debates glyph + owner first-run CTA (MEDIUM/LOW)

**Files:**
- Modify: `app/views/users/show.html.erb`
- Test: `spec/requests/profile_empty_spec.rb` (create)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/profile_empty_spec.rb
require "rails_helper"

RSpec.describe "Profile empty states", type: :request do
  it "offers the owner a first-run CTA on an empty Hoojahs tab" do
    user = create(:user)
    sign_in user
    get profile_path(user.username)
    expect(response.body).to include("No hoojahs yet")
    expect(response.body).to include(new_hujah_path)
  end

  it "does not show the CTA to a visitor viewing an empty profile" do
    owner = create(:user)
    visitor = create(:user)
    sign_in visitor
    get profile_path(owner.username)
    expect(response.body).to include("No hoojahs yet")
    expect(response.body).not_to include("Post your first hoojah")
  end
end
```

Confirm `profile_path` and `username` accessor (routes use `/u/:username`, helper `profile_path`).

- [ ] **Step 2: Run test to verify it fails**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/profile_empty_spec.rb`
Expected: FAIL — owner sees no CTA.

- [ ] **Step 3: Implement glyph map + owner CTA**

In `app/views/users/show.html.erb`, replace the empty branch (lines ~51-58) with:

```erb
        <% else %>
          <% empty = {"hoojahs" => {message: "No hoojahs yet", icon: "message-circle"},
               "responses" => {message: "No responses yet", icon: "message-circle"},
               "debates" => {message: "No debates yet", icon: "swords"}}.fetch(@active_tab) %>
          <% if @active_tab == "hoojahs" && @user == current_user %>
            <%= render "ui/empty_state", message: empty[:message], icon: empty[:icon],
                  align: :center, cta_label: "Post your first hoojah", cta_href: new_hujah_path %>
          <% else %>
            <%= render "ui/empty_state", message: empty[:message], icon: empty[:icon] %>
          <% end %>
        <% end %>
```

This fixes the `swords` glyph on the Debates tab (was the default `message-circle`) and adds the owner-only CTA.

- [ ] **Step 4: Run tests to verify they pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/profile_empty_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/users/show.html.erb spec/requests/profile_empty_spec.rb
git commit -m "Use swords glyph on profile Debates tab; add owner first-run CTA"
```

---

## Task 8: Branded error pages (HIGH)

**Files:**
- Create: `app/controllers/errors_controller.rb`, `app/views/errors/show.html.erb`
- Modify: `config/routes.rb`, `config/environments/production.rb`, `app/controllers/hujahs_controller.rb`, `app/controllers/tags_controller.rb`, `public/404.html`, `public/422.html`, `public/500.html`
- Test: `spec/requests/errors_spec.rb` (create)

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/requests/errors_spec.rb
require "rails_helper"

RSpec.describe "Branded error pages", type: :request do
  it "renders a branded 404 with the correct status" do
    get "/404"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("That page doesn't exist")
    expect(response.body).to include(root_path)
  end

  it "renders a branded 422 with the correct status" do
    get "/422"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("That request couldn't be processed")
  end

  it "renders a branded 500 with the correct status" do
    get "/500"
    expect(response).to have_http_status(:internal_server_error)
    expect(response.body).to include("Something went wrong")
  end

  it "no longer swallows a missing tag slug into a blank body" do
    expect { get "/t/definitely-not-a-real-tag" }
      .to raise_error(ActiveRecord::RecordNotFound)
  end
end
```

Rationale for the last example: in the test env `action_dispatch.show_exceptions` is off, so a propagating `RecordNotFound` surfaces as a raise (proving the controller no longer returns a blank `head :not_found`). In production `exceptions_app = routes` converts that same exception to the branded 404 — covered by the `/404` example.

- [ ] **Step 2: Run tests to verify they fail**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/errors_spec.rb`
Expected: FAIL — `/404` etc. have no route; tag slug currently returns 404 (not a raise).

- [ ] **Step 3: Create the ErrorsController**

```ruby
# app/controllers/errors_controller.rb
class ErrorsController < ApplicationController
  # Rendered by config.exceptions_app (production) for unhandled 404/422/500, and
  # reachable directly at /404, /422, /500. No resource to authorize; no login.
  skip_before_action :authenticate_user!, raise: false

  def show
    skip_authorization
    @status = params[:status].to_i
    @status = 500 unless [404, 422, 500].include?(@status)
    render :show, status: @status, formats: [:html]
  end
end
```

- [ ] **Step 4: Create the branded view**

```erb
<%# app/views/errors/show.html.erb — branded 404/422/500 in the app shell. %>
<%= render "shared/navbar" %>

<main class="max-w-xl mx-auto px-4 py-16">
  <%
    copy = {
      404 => {title: "That page doesn't exist", body: "The link may be broken or the hoojah was removed.", icon: "compass"},
      422 => {title: "That request couldn't be processed", body: "Something about that action didn't check out. Try again.", icon: "alert-triangle"},
      500 => {title: "Something went wrong on our end", body: "We've been notified. Please try again in a moment.", icon: "server-crash"}
    }.fetch(@status, {title: "Something went wrong on our end", body: "Please try again in a moment.", icon: "server-crash"})
  %>
  <div class="flex flex-col items-center text-center gap-4 bg-card border border-hairline rounded-none p-8 shadow">
    <%= lucide_icon copy[:icon], class: "w-10 h-10 text-grey" %>
    <h1 class="text-2xl font-extrabold text-ink tracking-tight"><%= copy[:title] %></h1>
    <p class="text-ink-2 text-sm"><%= copy[:body] %></p>
    <%= link_to "Back to feed", root_path, class: ds_button_classes(tone: "primary", size: :sm) %>
  </div>
</main>
```

Confirm the Lucide names `compass`, `alert-triangle`, `server-crash` resolve (`lucide_icon` raises on unknown names); substitute a known glyph if any is absent.

- [ ] **Step 5: Wire the routes**

In `config/routes.rb`, add near the top (after the `/up` health check, before `root`):

```ruby
  # Branded error pages (2026). In production config.exceptions_app = routes sends an
  # unhandled 404/422/500 here so users get the app shell instead of Rails' default
  # static page. `via: :all` because the failing request can carry any verb.
  match "/404", to: "errors#show", via: :all, defaults: {status: 404}
  match "/422", to: "errors#show", via: :all, defaults: {status: 422}
  match "/500", to: "errors#show", via: :all, defaults: {status: 500}
```

- [ ] **Step 6: Point production at the routes for exceptions**

In `config/environments/production.rb`, add (near `consider_all_requests_local`):

```ruby
  # Render unhandled exceptions through the app's own branded ErrorsController
  # (config/routes.rb: /404, /422, /500) instead of the static public/*.html.
  config.exceptions_app = routes
```

- [ ] **Step 7: Stop swallowing RecordNotFound into a blank body**

In `app/controllers/tags_controller.rb`, delete the `rescue ActiveRecord::RecordNotFound ... head :not_found ... end` block so `Hashtag.find_by!` propagates (→ branded 404 in prod; verify_authorized is skipped because the action raised).

In `app/controllers/hujahs_controller.rb`, in the `create` rescue (around line 87-90), replace `head :not_found` with a re-raise so the missing parent reaches the error handler:

```ruby
  rescue ActiveRecord::RecordNotFound
    raise
  end
```

(Or delete the rescue entirely — same effect. Keep whichever reads cleaner after StandardRB.)

- [ ] **Step 8: Rebrand the static fallback pages**

Rewrite `public/500.html`, `public/404.html`, `public/422.html` as self-contained HTML (no asset pipeline — these are the last-resort static fallbacks when the app can't boot). Match the palette: system font stack, primary `#415de6`, square corners, hairline `#f3f4f6`. Example for `public/500.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Something went wrong — Hoojah</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    body { margin:0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; background:#fff; color:#111827; }
    .wrap { max-width:32rem; margin:12vh auto; padding:2rem; text-align:center; border:1px solid #f3f4f6; box-shadow:0 1px 3px rgba(0,0,0,.08); }
    h1 { font-size:1.5rem; font-weight:800; margin:0 0 .5rem; }
    p { color:#374151; font-size:.9rem; }
    a { display:inline-block; margin-top:1rem; padding:.5rem 1.25rem; border:2px solid #415de6; color:#415de6; border-radius:9999px; text-decoration:none; font-weight:700; }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>Something went wrong on our end</h1>
    <p>We've been notified. Please try again in a moment.</p>
    <a href="/">Back to feed</a>
  </div>
</body>
</html>
```

Adjust the title/copy for `404.html` ("That page doesn't exist") and `422.html` ("That request couldn't be processed").

- [ ] **Step 9: Run tests to verify they pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/errors_spec.rb`
Expected: PASS (all four).

- [ ] **Step 10: Commit**

```bash
git add app/controllers/errors_controller.rb app/views/errors/show.html.erb config/routes.rb config/environments/production.rb app/controllers/tags_controller.rb app/controllers/hujahs_controller.rb public/404.html public/422.html public/500.html spec/requests/errors_spec.rb
git commit -m "Add branded ErrorsController for 404/422/500 and stop blank-body not_found"
```

---

## Task 9: Full-suite verification + quality gates

**Files:** none (verification only).

- [ ] **Step 1: StandardRB**

Run: `bundle exec standardrb` (append `--fix` then re-run if it reports offenses). Expected: no offenses.

- [ ] **Step 2: Brakeman + bundler-audit**

Run: `bundle exec brakeman -q` then `bundle exec bundler-audit check --update`. Expected: no new warnings.

- [ ] **Step 3: Prosopite N+1 sanity (tag page added a COUNT query)**

Run the tag + feed specs, then `grep -c 'N+1 queries detected' log/prosopite.log`. Expected: no new N+1 concentrated in the edited views (the `base.count` is a single aggregate, not per-row).

- [ ] **Step 4: Full CI**

Run: `bin/ci` (≈5 min: gates + db:test:prepare + tailwind build + full specs).
Expected: green. `bin/ci` builds Tailwind before RSpec so the CTA/error classes compile.

- [ ] **Step 5: Tailwind bundle spot-check**

Confirm the CTA pill and error-page classes rendered (they come from real ERB, so they compile). If any interpolated class was introduced (none in this plan), add an `@source inline(...)` entry.

- [ ] **Step 6: Final commit (if any gate autocorrected)**

```bash
git add -A
git commit -m "Apply StandardRB autocorrections for empty/error-state work"
```

---

## Self-Review (author checklist — completed)

- **Spec coverage:** every gap in the spec maps to a task — global feed (T2), tag page + count (T3), stance-filter void (T4), notifications filtered-empty (T5), search zero-results + empty cloud (T6), profile debates glyph + owner CTA (T7), branded errors + blank-body not_found (T8), primitive CTA slot (T1), Following reword + "No responses yet" grammar (T2/T4). Verdict small-N and blocked-profile surface are explicitly out of scope in the spec.
- **Placeholder scan:** no TBD/TODO; every code step shows full code.
- **Type/name consistency:** `cta_label`/`cta_href` used identically in T1 primitive and all callers; `notifications_empty_message` defined in T5 helper and called in both notification views; `empty` Stimulus target name consistent between view (T4 step 3) and controller (T4 step 4); `@count` defined in T3 controller and used in T3 view.
