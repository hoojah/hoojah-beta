# Animation catalog (find-animation-opportunities) — 2026-08-28

Repo motion vocabulary (extend these, never invent parallel ones):
- Easing: `--ease-out: cubic-bezier(0.23, 1, 0.32, 1)`; spring-ish `cubic-bezier(.34,1.56,.64,1)` (used by `.hrise`).
- Keyframes already in `application.css`: `hpop hfloat hboom hray hbar hbreathe hrise hfade`.
- Global `@media (prefers-reduced-motion: reduce)` guard now present (Task D0).

**Finding: the interface is already close to right.** Press feedback (`active:scale-95`), menu open
(`ui/_menu` opacity/transform 200ms), debate-turn enter (`.debate-turn-enter` hrise 220ms), the
vote-hero boom (`hpop/hboom/hray`), the composer expand (hrise), and the live-pill breathe all exist.
The gaps below are the real ones; the expressive tier (roll-up) is the owner's explicit ask.

## Part 1 — Opportunities (ordered by leverage)

| # | Location | Today | Purpose | Frequency | Suggested motion |
|---|----------|-------|---------|-----------|------------------|
| 1 | `<dialog>` via `dialog_controller` (flag `_flag_dialog`, challenge `_challenge_dialog`, profile-edit) | `showModal()` snaps open; backdrop appears instantly | Spatial / prevent jarring | Occasional | CSS-only: `dialog { opacity:0; transform: scale(.97); transition: opacity 160ms var(--ease-out), transform 160ms var(--ease-out), overlay 160ms, display 160ms; transition-behavior: allow-discrete } dialog[open]{opacity:1;transform:none} @starting-style{ dialog[open]{opacity:0;transform:scale(.97)} } dialog::backdrop{ opacity:0; transition: opacity 160ms } dialog[open]::backdrop{opacity:1}`. No JS change. |
| 2 | Appended feed cards — `hujahs/index.turbo_stream.erb` `turbo_stream.append "hujah-feed"` (Load more) | New cards pop in instantly | Preventing a jarring change | Occasional | Add a `.hujah-card-enter` class to the appended card wrapper that runs `animation: hrise 240ms var(--ease-out)` (mirror `.debate-turn-enter`). Only appended cards animate; first paint stays static (apply the class in the turbo_stream append render path, not in `_hujah_card` itself, so scroll/first-paint doesn't re-trigger). |
| 3 | Notification remove — `notifications/destroy.turbo_stream.erb` `turbo_stream.remove` | Card vanishes instantly on mark-read | Spatial consistency | Occasional | Intercept `turbo:before-stream-render` for `action=remove` on a `.notification-card`: play a 160ms `opacity→0 + translateX(8px)` then remove. Small shared helper in `application.js` (respect reduced-motion: skip to immediate remove). |
| 4 | Vote/response/conviction counts in `_hujah_card` footer + `_vote_hero` | Numbers jump on Turbo-Stream replace | State indication + delight | Occasional | Expressive tier (owner ask): a `number_roll` Stimulus controller (better-stimulus) that tweens from the old to new integer over ~300ms on connect when the value changed; reduced-motion → set final value immediately. |
| 5 | Feed `_vote_bars` segments (`:67` `style="width:N%"`) | Segment widths snap on vote replace | State indication | Occasional | Add `animation: hbar 420ms var(--ease-out)` to the segment fills so they grow to width on the post-vote replace (the hero already transitions width). Lower priority — verify it doesn't feel busy on first feed paint; if it does, gate to the replaced partial only. |

## Part 2 — Rejected (already handled or fails the Gate)

- Press feedback on buttons/pills — **already `active:scale-95` app-wide** (`_vote_bars:91`, composers, navbar). Tens/day. No change.
- Dropdown/menu open — **already animates** (`ui/_menu` `transition: opacity/transform 200ms var(--ease-out)`). Done.
- Debate-turn enter — **already `.debate-turn-enter` hrise 220ms**. Done.
- Vote-hero cast celebration — **already `hpop/hboom/hray`** (`_vote_hero:123-125`). This is the delight moment; leave it.
- Live-debate pill dot — **already `hbreathe`** (`_live_debate_strip:30`, `_debate_scoreboard:29`). Done.
- Composer expand — **already `hrise`** (`_argument_composer:68`, `_inline_composer`). Done.
- Feed/profile tab underline slide — **Rejected: tabs switch often + already carry a clear filled/underline active state**; a sliding underline adds motion to a frequent action for little gain.

## Part 3 — Verdict
This UI needs little more motion; it is already close to right. The highest-leverage single addition is
**#1 (dialog open/close)** — it's CSS-only, purely spatial, and the only modal surface that currently
teleports. #2 and #3 close the list enter/exit gaps; #4 is the owner's expressive roll-up (delight
tier, gated by reduced-motion). Implement in that order; #5 is optional.
