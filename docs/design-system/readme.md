# Hoojah Design System

**Hoojah** is a Malaysian social debate platform ("where Malaysia's brilliant minds come to debate about current issues and vote for what they feel is important"). Users post a **hujah** (a stance or claim), gather **agree / neutral / disagree** votes, thread stance-tagged responses, and escalate any argument into a one-on-one turn-based **debate** with a spectator verdict. Live at https://hoojah.rudzainy.com

## Source
- Attached codebase: `hoojah-beta/` — Rails 8.1 server-rendered Hotwire app (Turbo + Stimulus), Tailwind CSS v4, `lucide-rails` icons. Ground truth files: `app/assets/tailwind/application.css` (the `@theme` palette), `app/views/**` (all UI), `app/helpers/icons_helper.rb`, `app/models/badge.rb`.
- One product/surface: the **web app** (feed, single hujah, compose/respond, profile, notifications, debates, trending, dashboard, auth).

## Core domain vocabulary
- **hujah / hoojah** — a claim (top-level) or a stance-tagged response ("argument")
- **Stances** — agree (orange `#fcaf45`, thumbs-up), neutral (pink `#e1306c`, minus), disagree (purple `#833ab4`, thumbs-down). Neutral is PINK — never render it grey.
- **Debate** — challenger vs opponent, alternating turns, states pending/active/concluded/declined; spectator verdict (challenger/opponent/draw)
- **Badges** — First Hoojah (award), First Argument (message-circle), First Follower (users), First Debate (swords)

## CONTENT FUNDAMENTALS
- Direct second person, casual, lightly playful. "What's your hoojah?", "Add some jazz to your profile!", "Make your argument…", "Challenge to debate", "Click here to sign up!"
- Product nouns lowercase mid-sentence ("your hoojah", "a debate"); the brand "Hoojah" capitalized.
- Handles always `@username` (prefixed @, shown next to full name). Timestamps compact ("Apr 16").
- Questions & prompts drive UI copy ("Do you AGREE? NEUTRAL? DISAGREE?" in share text; "Why are you flagging this hoojah?"). ALL-CAPS used for stance emphasis in share copy only.
- Empty states are plain, friendly sentences: "No response yet", "No debates yet — challenge a response to start one.", "Nothing trending yet.", "Waiting for @user…"
- Emoji appear in USER content (seed bios: 🥥 ✈️ ❤️) but never in UI chrome.
- Malaysian context: sample users/content are Malaysian public figures, brands, places.

## VISUAL FOUNDATIONS
- **Colors**: primary `#415de6` (indigo-blue: links, brand, active tab, profile header bg); stance trio agree/neutral/disagree; ink `#343a40`, muted `#8e8e8e`, faint `#bac2ca`. Tailwind grays for hairlines (`#f3f4f6`), field borders/tracks (`#e5e7eb`), hover fills (`#f9fafb`).
- **Type**: system sans stack only — NO webfonts (nothing to substitute). Body copy of a hujah: 18px `leading-snug` (20px on the detail page). UI text 14px; micro-labels 12px, uppercase + tracking-wide for statuses. Weights: medium for names/CTAs, semibold section heads, bold rare.
- **Cards**: white, **square corners**, Tailwind `shadow`, hairline `#f3f4f6` internal dividers, stacked with 8px gaps on a white page. Compact child/profile cards carry an **8px stance-colored left border** — a real motif of this brand.
- **Buttons**: pill (`rounded-full`) with **2px colored border**, white bg, colored text + `shadow`; solid pill for primary submit (Save changes). Rect `rounded` solid buttons on auth screens & the signup CTA. Circular 44px vote buttons (2px stance border; filled + white icon when voted). Press state: `active:scale-95`. Hover on menu items: `bg-gray-100`/`gray-50`.
- **Bars**: 8px tall rounded track `#e5e7eb`, stance-colored fill by %, percentage label right-aligned.
- **Nav**: fixed top, 56px, `bg-white/90 backdrop-blur`, hairline bottom border. Content column `max-w-xl` (576px) centered; lg viewports add a 256px lazy trending sidebar.
- **Profile header**: full-bleed primary-blue block, white text/icons, centered 96px round avatar, white-on-blue pill buttons, translucent white badge chips (`bg-white/20`).
- **Dialogs**: native `<dialog>`, `rounded-lg`, `shadow-lg`, `backdrop:bg-black/40`, hairline header with title + X close.
- **Menus**: `<details>` dropdowns — white, `shadow`, `rounded`, tiny grey heading, hover rows.
- **Animation**: essentially none — `transition` + `active:scale-95` on vote buttons; no keyframes, fades, or bounces.
- **No** gradients (except the logo), no blur except the navbar, no imagery/illustrations, no dark mode.

## ICONOGRAPHY
- **Lucide** everywhere (the Rails app uses `lucide-rails`; this system loads lucide from CDN — see `components/core/Icon.jsx`). Stroke icons, 2px, `currentColor`; sized w-4 h-4 (16px) inline, w-6 h-6 (24px) in the navbar.
- Full inventory used: flame, message-square-plus, message-circle, bar-chart-2, bar-chart-3, thumbs-up, minus, thumbs-down, share-2, arrow-left, more-horizontal, flag, swords, map-pin, globe, users, user-plus, user-check, user-x, clock, ban, lock, edit, x, megaphone, at-sign, award, trash-2, bell.
- Stance mapping (icons_helper.rb): agree→thumbs-up, neutral→minus, disagree→thumbs-down.
- No icon font, no emoji in chrome, no PNG icons. Logo is the only decorative SVG.

## Assets
- `assets/logo.svg` — gradient "hoojah" wordmark (green→blue radial). NOTE: source file had orphaned `.st0–.st6` classes (its `<style>` block was lost upstream); fills restored here by mapping each class to its sibling gradient id.
- `assets/app-icon-512.png` — app icon; `assets/pinned-tab.svg` — monochrome mark; `assets/loading.svg` — spinner.
- User avatars in production come from Cloudinary (not copyable) — use `core/Avatar` initials fallback.

## Inferred (not in source — flag to designers)
- `border-read` / `border-unread` notification classes have NO color definition in the source `@theme` (latent gap). Tokens here define unread = neutral pink, read = light-grey, matching the unread dot which uses `bg-neutral`.
- Page background: plain white (no `.body` class definition found).

## Index
Root manifest:
- `styles.css` — the single entry point consumers link. Imports only.
- `tokens/colors.css`, `tokens/typography.css`, `tokens/layout.css`, `tokens/base.css` — all 72 custom properties.
- `assets/` — `logo.svg`, `app-icon-512.png`, `pinned-tab.svg`, `loading.svg`.
- `guidelines/` — 16 foundation specimen cards (Colors, Type, Spacing, Brand).
- `components/` — the reusable primitives (below).
- `ui_kits/web/` — click-through recreation of the web app; see its own `README.md`.
- `thumbnail.html` — the design system's tile.
- `SKILL.md` — agent skill entry point.

### Components
Each directory holds `<Name>.jsx`, `<Name>.d.ts`, `<Name>.prompt.md` and one `@dsCard` HTML.

- **components/core/** — `Icon` (+ `STANCE_ICON`, `STANCE_COLOR`), `Avatar`, `Button`, `Card` (+ `Divider`), `EmptyState`
- **components/navigation/** — `Navbar`, `FeedTabs`, `SubNav`, `DropdownMenu` (+ `MenuHeading`, `MenuItem`, `MenuSeparator`)
- **components/voting/** — `VoteButton`, `VoteBars`, `StancePicker`, `ResponseFilterTabs`
- **components/hujah/** — `HujahCard`, `HujahHeader` (+ `ParentStub`), `CompactHujahCard` (+ `ChallengeLink`), `ShareMenu`
- **components/social/** — `ProfileHeader`, `FollowButton`, `BadgeChip` (+ `BADGES`), `UserRow`, `NotificationCard` (+ `NotificationAction`), `TrendingList`, `PinnedCTA`
- **components/debate/** — `DebateCard` (+ `DebateStateLabel`, `DebateStatus`, `DEBATE_STATE_COLOR`), `DebateTurn`, `TurnComposer`, `Verdict`
- **components/forms/** — `TextField`, `TextAreaField`, `Checkbox`, `FormError`
- **components/analytics/** — `StatChip`, `DistributionBar`
- **components/overlays/** — `Dialog` (+ `DialogChoiceList`, `DialogChoice`)

The inventory above is exactly what `hoojah-beta/app/views/**` defines — one component family
per partial or partial group. No Toast, Tooltip, Avatar-group, Tabs-beyond-these, Skeleton or
dark-mode variants exist in the source, so none were invented.

### Intentional additions
- `core/Icon` — a React wrapper for the Lucide set, standing in for the Rails `lucide_icon` helper.
- `core/Avatar` — initials fallback, since production photos come from Cloudinary and can't be copied.
- `core/EmptyState` — the source repeats the same faint icon+sentence markup in six views; extracted once.
- `core/Card` / `Divider` — the repeated `shadow bg-white` + `border-gray-100` idiom, extracted.
