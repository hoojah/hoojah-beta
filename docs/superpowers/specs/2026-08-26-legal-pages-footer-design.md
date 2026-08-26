# Public FAQ / Privacy / Terms pages + sidebar footer card

**Date:** 2026-08-26
**Status:** Approved — ready for implementation

## Goal

Ship three publicly accessible informational pages — **FAQ**, **Privacy Policy**, and
**Terms of Service** — and surface links to them from a footer card placed **below the
trending section** in the feed's desktop sidebar (Twitter-style footer card, per the
reference screenshot).

Content is treated as **final and shipped** (no "draft" annotations anywhere in
user-facing content). It will be revised in the future as needed. A standard
`Last updated` date is allowed — it is normal for legal pages and is not a draft flag.

## Non-goals

- No CMS / markdown pipeline / admin editing — content is static ERB.
- No cookie-consent banner, no "About/Blog/Jobs/…" pages from the reference image.
  Only the three real, working links ship.
- No new sidebar on pages that don't already have one. Footer card appears **only** in
  the feed sidebar (`app/views/hujahs/index.html.erb`).

## Architecture

Mirrors the existing public, Pundit-exempt `TrendingController` pattern exactly.

### Controller

`app/controllers/pages_controller.rb`

```ruby
class PagesController < ApplicationController
  # Public informational pages (FAQ / Privacy / Terms). No auth: anonymous visitors
  # must be able to read them. Nothing to authorize, so skip_authorization satisfies
  # ApplicationController's after_action :verify_authorized (same shape as TrendingController).
  def faq
    skip_authorization
  end

  def privacy
    skip_authorization
  end

  def terms
    skip_authorization
  end
end
```

No global `authenticate_user!` exists, so these are reachable while signed out.

### Routes

Hand-written paths with explanatory comments (the routes file uses no `resources`),
added near the trending/search block in `config/routes.rb`:

```ruby
# Public informational pages (2026). Static, no auth — anyone (signed out included)
# can read the FAQ and the legal pages. MAIN routes (not Api::V1); they never write,
# so CSRF posture is irrelevant. Addressed by plain path, not a record slug.
get "/faq",     to: "pages#faq",     as: :faq
get "/privacy", to: "pages#privacy", as: :privacy
get "/terms",   to: "pages#terms",   as: :terms
```

### Views

- `app/views/pages/faq.html.erb`
- `app/views/pages/privacy.html.erb`
- `app/views/pages/terms.html.erb`
- `app/views/pages/_legal_chrome.html.erb` — shared page chrome partial: renders
  `shared/navbar`, a `<main class="max-w-xl mx-auto px-4 py-6">`, the design-system
  card (`ui/_card` layout partial), an `<h1>` title, an optional `Last updated` line,
  and yields the body via a block. Keeps the three pages visually consistent and DRY.

Prose is styled with **literal** Tailwind utilities (headings, paragraphs, lists) in
house style: grey body text, `#415de6` (`text-primary`) links, system font, no dark
mode, square corners. No interpolated class names anywhere in these views, so **no
`@source inline` safelist work is required** (per the Tailwind gotchas in CLAUDE.md).

`ui/_card` is a **layout** partial — invoked as
`render layout: "ui/card", locals: {...} do … end`, never `render partial:`.

### Sidebar footer card

New partial `app/views/shared/_footer_links.html.erb`, rendered in the feed's
`<aside>` in `app/views/hujahs/index.html.erb` **directly below** the trending
turbo_frame, separated with `mt-6`.

House style: white square-cornered card, `shadow`, `#f3f4f6` hairline divider. Grey
links (`text-grey`, `hover:text-primary`, matching the trending list rows) laid out as
`FAQ · Privacy · Terms`, plus a `© 2026 Hoojah` line. Uses `link_to faq_path` etc.
Only real, working links — no dead links from the reference image.

## Content (final)

Substantive and **Hoojah-specific**, grounded in how the app actually works. Written
in plain, clear language.

### FAQ (`faq.html.erb`)
Q&A covering:
- What is Hoojah / what is a *hujah* (a claim you post for others to weigh in on).
- Voting: agree / neutral / disagree; neutral is a real stance, not an abstention.
- **Secret ballot** — who you voted for is private; the author cannot see individual
  voters. Only aggregate tallies are shown.
- Responses/threads: stance-tagged replies form a tree under a hujah.
- **Debates**: escalating an argument into a one-on-one, turn-based debate with
  alternating rounds and a **spectator verdict**; debates idle > 7 days auto-conclude.
- **Follows**: accepted-only; following a private account creates a pending request.
- **Blocks**: bidirectional — blocking hides you from them and them from you.
- Badges, trending (how the feed surfaces active claims), and account basics.

### Privacy Policy (`privacy.html.erb`)
Sections:
- Who we are & scope.
- Information we collect (account details, content you post, votes, usage).
- **Vote privacy / secret ballot** — votes are recorded to compute tallies but are not
  attributed to you publicly or to hujah authors.
- Cookies & sessions (auth session cookie; no third-party ad tracking).
- Images & media hosting (Cloudinary in production).
- How we use information; legal bases.
- Sharing & disclosure (we don't sell personal data).
- Data retention & deletion.
- Your rights (access, correction, deletion) with a Malaysian **PDPA 2010** reference.
- Blocking & privacy controls (private accounts, blocks).
- Children / minimum age.
- Changes to this policy; contact.

### Terms of Service (`terms.html.erb`)
Sections:
- Acceptance of terms.
- Eligibility & minimum age.
- Your account (accuracy, security, responsibility for activity).
- Acceptable use / prohibited conduct (harassment, illegal content, spam, impersonation,
  circumventing blocks or vote privacy, scraping).
- Content ownership & the licence you grant Hoojah to display your content.
- Debate conduct & the spectator-verdict system.
- Moderation, suspension & termination.
- Disclaimers & limitation of liability.
- Governing law — **Malaysia**.
- Changes to the terms; contact.

## Testing

TDD. `spec/requests/pages_spec.rb`:

- `GET /faq`, `/privacy`, `/terms` each return **200 for anonymous** users.
- Each also returns **200 for a signed-in** user (regression on `verify_authorized`).
- Each response includes a distinctive heading/marker string for that page.
- The feed (`GET /`, signed-in) renders the footer card with links to `faq_path`,
  `privacy_path`, `terms_path`.

No new system spec required (no JS behaviour). Existing suite must stay green
(`bin/ci`).

## Execution plan (orchestration)

- **Fable** (architect): produce/verify the task breakdown and, at the end, review the
  implementation against this spec.
- **Opus 4.8 subagents** (subagent-driven development): execute each task TDD-first
  (write failing request specs → implement controller/routes/views → green).
- Merge the feature branch back into `master` when the full suite is green.

## Risks / notes

- Two pre-existing uncommitted files in the working tree (`config/environments/production.rb`,
  `config/storage.yml`) are **not** part of this work and must be excluded from all commits.
- Keep the `# 🚅`-free routes convention: every new route carries a why-comment.
- Tailwind: no interpolated classes in the new views → no safelist changes.
