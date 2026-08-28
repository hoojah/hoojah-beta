# UI fixes + delete-hujah flow — design

Date: 2026-08-28
Branch: `ui-fixes-and-delete-hujah`

Batch of five targeted UI/UX corrections plus one net-new feature (delete a hujah).
All server-rendered Hotwire; token-driven Tailwind (never hardcode stance hex).

---

## 1. Double hashtag glyph (`# #Malaysia`)

**Cause:** the hashtag-feed pill prints both a lucide `hash` icon *and* a literal `#`
before the tag text, so with `gap-2` it reads as `# #Malaysia`.

**Fix:** drop the literal `#`, keep the `hash` icon (the icon *is* the hash marker).
- `app/views/tags/show.html.erb:11` — `<span>#<%= @tag.display %></span>` → `<span><%= @tag.display %></span>`.
- `app/views/search/_result_hashtag.html.erb` — same icon + literal-`#` pattern; remove the literal `#`, keep the icon.

Leave the *text-only* pills (`hujahs/show`, `_hashtag_chips`, search chips) untouched —
they render a single `#` with **no** icon and are already correct.

## 2. Feed-card indicator row (`app/views/hujahs/_hujah_card.html.erb:67-81`)

Four changes to the footer indicator row:

1. **Un-link the icons.** The vote (`bar-chart-3`) + response (`message-circle`) counts
   are currently wrapped in one `link_to hujah_path`. Remove the anchor; render them as
   plain spans (consistent with the already-un-linked body — the thread is reached via
   the persistent "Jump in" pill).
2. **Conviction icon → bolt.** Change `heart` to `zap` to match the hujah **show** page
   (`_vote_hero.html.erb:41` uses `zap` for conviction). Keep `text-primary`.
3. **Tooltips.** Add a native `title=` on each indicator group describing what it means:
   votes → "Votes cast", responses → "Responses", conviction → "Conviction votes".
   (Native `title` needs no Tailwind safelisting.)
4. **Dot before conviction.** Currently one `·` sits between votes and responses. Add a
   second `·` between the response count and the conviction bolt (rendered only when the
   conviction indicator is — i.e. inside the `conviction_count > 0` guard).

Update `spec/views/hujahs/_hujah_card_spec.rb` for the un-linked icons and `zap`.

## 3. Profile tabs don't highlight (`app/views/users/show.html.erb`)

**Cause:** `_profile_tabs` is rendered **outside** the `profile-list` Turbo Frame, but tab
links target that frame — so a click swaps only the list, never re-rendering the tab bar,
and the active-pill class (recomputed server-side) never reaches the DOM.

**Fix:** move the `_profile_tabs` render **inside** the `turbo_frame_tag "profile-list"`
(above the list), so each tab click re-renders the frame *including* the tab bar with the
new `@active_tab`. The controller already sets `@active_tab` per request, and both
`show.html.erb` and the frame's turbo-stream/HTML response render through the same frame,
so the recomputed `bg-primary text-white` / `aria-current="page"` now lands. No Stimulus
needed. Verify the frame's `target: "_top"` and any load-more pagination still work.

## 4. Dropdown tap targets on small screens (`design_system_helper.rb` `ds_menu_item_classes`)

**Cause:** `MENU_ITEM_BASE` is `px-3 py-1` at every breakpoint — ~24-28px tall rows, well
under the ~44px touch target.

**Fix:** make the vertical padding responsive in `MENU_ITEM_BASE`: `py-2.5 sm:py-1`
(comfortable on phones, unchanged on `sm+`). Safelist note: these are static utilities in a
Ruby **string literal**, so Tailwind extracts them — no `@source inline` needed, but confirm
`py-2.5` and `sm:py-1` compile. Affects all 11 menu call sites (navbar, both share menus,
more-actions) — that is the intent.

## 5. Edit-profile modal won't scroll on large screens (`app/views/users/_profile_edit.html.erb:70-75`)

**Cause:** the native `<dialog>` has `max-w-md` but **no** `max-height`/`overflow`, so content
taller than the UA `max-height` is clipped, not scrollable.

**Fix:** make the dialog a flex column capped at the viewport with the body scrolling:
add `max-h-[90dvh] overflow-hidden flex flex-col` to the `<dialog>`, keep the header as a
non-shrinking row, and wrap the form's field stack in an `overflow-y-auto` region so the
header (and Save button, if pinned) stay put while fields scroll. No Stimulus change.

## 6. Delete a hujah — HTML/Turbo flow

Decisions (locked with product owner):
- **Hard destroy** (`hujah.destroy`), mirroring the existing JSON API `#destroy`.
- **Blocked when the hujah has replies or debates.** If `hujah.children.any? ||
  hujah.debates.any?`, refuse with an alert — a destroy may only remove a "clean" claim,
  never cascade-wipe other users' responses or an escalated debate.
- **Native `turbo_confirm`** (no custom dialog).
- **Show page only** — replace the greyed `Delete hoojah (Slice 2)` placeholder in the
  `…` More-actions menu (`app/views/hujahs/show.html.erb:50`). Feed-card menu unchanged.

Reuses that already exist: `HujahPolicy#destroy?` (owner-only, nil-safe) and its policy
spec; the API destroy request spec (shape to mirror).

Build list:
1. **Route:** in the HTML block of `config/routes.rb` (~line 57), add
   `delete "/hoojah/:slug", to: "hujahs#destroy"` with a comment (CSRF-on main route, not API).
2. **Controller:** `HujahsController#destroy` — add `:destroy` to the `authenticate_user!`
   `before_action`; `@hujah = Hujah.friendly.find(params[:slug])`; `authorize @hujah`
   (uses `destroy?`); guard: if it has children or debates, `redirect_back
   fallback_location: hujah_path(@hujah.slug), alert: …, status: :see_other` and return;
   else `@hujah.destroy` and `respond_to` — `turbo_stream` + `format.html { redirect_to
   root_path, status: :see_other }`.
3. **Model:** add `has_many :notifications, dependent: :destroy` (or `:nullify`) on `Hujah`
   — today notifications carrying `hujah_id` are orphaned on destroy. Pick `:destroy`
   (a notification about a gone hujah is dead). Verify no other orphan (schema FK check).
4. **Turbo Stream view:** `app/views/hujahs/destroy.turbo_stream.erb` →
   `turbo_stream.remove dom_id(@hujah)`. For this to hit a feed card, give `_hujah_card`
   a stable `id: dom_id(hujah)` (via the `ui/_card` `id:` local). On the show page the html
   redirect to root handles it; the turbo_stream is for when delete is triggered where the
   card is in a list.
5. **Menu control:** replace the placeholder `<span>` with a `button_to "Delete hoojah",
   hujah_path(@hujah.slug), method: :delete, data: {turbo_confirm: "Delete this hoojah? This
   can't be undone."}`, styled as a destructive menu row (`ds_menu_item_classes(tone:
   "neutral")`), owner-guarded (guard already present).
6. **Specs:** request spec (401 unauth / 403 non-owner / blocked-with-replies / owner
   success + `Hujah.exists?` false + redirect); policy spec already covers `destroy?`;
   a system spec mirroring `flag_spec` (open More actions → Delete → confirm → card gone).

## Review & landing

Implementer subagents (disjoint files) → independent review by rails-simplifier,
rails-security-auditor, better-stimulus (any Stimulus/Hotwire touch), superpowers
code-reviewer, plus a Fable-orchestrated synthesis of the review → batched fixes →
`bin/ci` green → merge to `master` → push.
