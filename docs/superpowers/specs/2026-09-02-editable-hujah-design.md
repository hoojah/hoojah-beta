# Editable Hujah — Design

**Date:** 2026-09-02
**Status:** Approved (brainstorm complete). Ready for implementation plan.

## Overview

Let a hujah's author edit their post. Three independent, owner-only slices delivered on
one "edit your hujah" surface:

1. **Edit body** — time-boxed to 15 minutes, blocked once any conviction is cast. Top-level
   posts **and** replies.
2. **Change visibility** — anytime, but *tightening* the audience permanently purges the
   votes and arguments of everyone who loses access, snapshots the pre-change post into a
   read-only archive, and redirects those users' old links to it. Top-level only.
3. **Custom stance labels** — authors who have posted 10+ default top-level hujahs can rename
   Agree/Neutral/Disagree inline on the composer. Immutable after creation. Top-level only.

Every new controller action calls `authorize` exactly once (the app's
`verify_authorized` after-action requires it) against new `HujahPolicy` methods. New
write actions live on **main routes, not `Api::V1`**, so CSRF stays enforced (per the
routing convention).

**Recommended build order: Slice 1 → Slice 3 → Slice 2** — the destructive slice ships last,
with the most care. Slices are otherwise independent.

---

## Slice 1 — Edit body (time-boxed)

### Rule
A hujah's body is editable when **all** hold:
- viewer is the author,
- `moderation_status` is `active`,
- `created_at > 15.minutes.ago`,
- `conviction_count == 0`.

The window closes at **15 minutes OR the first conviction, whichever comes first** —
permanently. Applies to both top-level hujahs and replies (child hujahs).

### Model — `app/models/hujah.rb`
- `EDIT_WINDOW = 15.minutes`
- `def body_editable? = moderation_active? && conviction_count.zero? && created_at > EDIT_WINDOW.ago`
- Add column `body_edited_at :datetime` (nullable). Set it in `update` **only when the body
  text actually changes** — `updated_at` is unreliable as an "edited" signal because
  `cast_vote` writes counter columns and touches `updated_at`.
- `def body_edited? = body_edited_at.present?`
- `notify_mentions` is currently `after_create_commit` only (edit-mentions were explicitly
  deferred at `hujah.rb:268`). Add edit-aware mention notification: on a body update, notify
  **only newly-added** @mentions (diff mention set old-vs-new). Existing mentions do not re-fire.
- `sync_hashtags` (`after_save_commit`, `hujah.rb:211`) already runs on update — no change.
- FriendlyId `:history` (`hujah.rb:278-288`) already regenerates the slug on body change and
  keeps old slugs redirecting — no change.

### Policy — `app/policies/hujah_policy.rb`
Add `edit?` and `update?`: `owner? && !record.moderation_removed? && record.body_editable?`.
(Mirror the existing `destroy?` owner + not-removed guard at `hujah_policy.rb:40`.)

### Routes — `config/routes.rb` (near the existing hoojah block, ~`:54-64`)
- `get  "/hoojah/:slug/edit" => "hujahs#edit",   as: :edit_hujah`
- `patch "/hoojah/:slug"     => "hujahs#update"`

Each route carries a comment explaining its shape (house convention: no `resources`).

### Controller — `app/controllers/hujahs_controller.rb`
- Add `:edit, :update` to the `authenticate_user!` before-action (`:2`).
- `edit`: load by slug, `authorize @hujah` (edit?), render the compose form in edit mode.
- `update`: load, `authorize @hujah` (update?), re-check `body_editable?` server-side and
  **fail closed** (redirect back with an alert) if the window has closed between GET and PATCH.
  Permit **body only** plus `allow_debates` **for top-level records only** (replies have no
  `allow_debates`). Set `body_edited_at` when body changed. Never permit stance/visibility/
  custom-label params here.

### View — `app/views/hujahs/_compose_form.html.erb`
Add an **edit mode**: switch `form_with` url/method to the PATCH edit path; hide the stance
picker, visibility select, and custom-label affordance; keep body + (top-level only) the
allow_debates toggle. Add an "Edit" item to the owner menu on `show.html.erb` (`:44-65`)
and `_card_menu`, shown only when `body_editable?`. Render "· edited" near the timestamp when
`body_edited?`.

### Tests
- Model: `body_editable?` truth table (fresh / >15min / conviction present / removed);
  `body_edited_at` set only on body change, not on a vote.
- Policy: `edit?`/`update?` owner-only + window + conviction + removed.
- Request: PATCH succeeds in-window, 403/redirect out-of-window and after conviction; new
  @mention notified, pre-existing mention not re-notified; slug history redirect still works.
- System: owner edits within window; edit affordance absent after window/conviction.

---

## Slice 2 — Change visibility (permanent, destructive; top-level only)

Visibility change is available anytime to the owner of a top-level hujah. Behaviour splits on
direction.

### Routes & controller — `config/routes.rb`, `HujahsController`
- `get   "/hoojah/:slug/visibility" => "hujahs#visibility_edit", as: :visibility_hujah` —
  the change form; when the chosen value tightens, this is also the confirmation screen
  (counts + entanglement list + typed-confirm field).
- `patch "/hoojah/:slug/visibility" => "hujahs#update_visibility"` — applies the change.
- Both authorize against `HujahPolicy#change_visibility?` (owner + top-level + not-removed).
  `update_visibility` runs the loosening path or the destructive purge path (below) inside a
  transaction, re-checking everything server-side.

### Direction
- **Loosening** (wider audience: `private_only → followers_only → visible_public`) — simply
  updates `visibility`. No purge, no archive, no confirmation beyond a normal submit.
- **Tightening** (narrower audience) — the destructive path below.

### Affected participants
A **participant** is any user (≠ author) who cast a vote on the hujah **or** authored an
argument anywhere in its subtree. A participant is **affected** when, evaluated against the
**new** visibility, `visible_to?` returns false. Compute prospectively by reusing the
`Hujah#visible_to?` logic (`hujah.rb:118-129`) with the candidate visibility value.
The author is never affected. Already-blocked users are already invisible and are not
double-counted.

Purge **overrides conviction locks** — a now-invisible user's conviction vote is removed
along with everything else. The point of the feature is that the author sheds all
participation from users who lost access.

### Entanglement block (fail closed)
An affected user's **argument** (child hujah) is *entangled* when it has replies, votes, or a
debate from **other** users, or is in an **active debate**. If any affected argument is
entangled, the whole visibility change is **blocked**. The confirmation screen lists the
entangled arguments. Resolution is on the **argument owner's** side — they must either:
- **delete** the argument, or
- **promote** it to a standalone top-level hujah.

**New capability — promote argument to top-level:**
- Route: `post "/hoojah/:slug/promote" => "hujahs#promote", as: :promote_hujah`.
- `HujahsController#promote`: owner-only (`authorize`), only valid on a child (`parent_id`
  present). Sets `parent_id = nil` (the whole subtree travels with it — descendants keep
  pointing at it), enforces top-level validations (body ≥ 8 chars), regenerates slug.
  A promoted argument loses its stance-toward-parent context (its `vote` column is cleared),
  becoming an independent claim.
- Policy: `promote?` = owner + child + not-removed.

### Confirmation UX
Tightening is a two-step action. The confirmation names **exact counts** — *N users, V votes,
A arguments* to be permanently removed — plus any blocking entanglements. If nothing blocks,
the user must **type a confirmation word** to proceed. The server **recomputes** counts and
**re-checks** entanglement at submit time (never trust client-supplied counts; fail closed on
any newly-appeared entanglement).

### Archive snapshot (read-only, immutable)
Before purging, snapshot the pre-change post:
- **`hujah_archives`** — `hujah_id` (integer, **no cascading FK**, mirrors the FK-less
  notification pattern so it survives the live hujah's later deletion), `snapshot` (jsonb:
  body, author display, timestamp, all four counts, effective stance labels, and the
  then-visible argument tree — each argument's author/body/stance/counts), `visibility_before`
  (int), `created_at`, and a `token` for addressing.
- **`hujah_archive_participants`** — `archive_id`, `user_id`, unique on the pair. One row per
  purged user, mapping them to the archive captured at their purge moment.

The archive renders the **full frozen post including the purged user's own vote and
arguments** — a faithful record of what they participated in. Read-only; no actions.

### Purge (single transaction, row-locked)
Order:
1. Build the snapshot from **current** state; create the `HujahArchive`.
2. Insert `HujahArchiveParticipant` rows for every affected user.
3. Delete affected users' votes and their now-childless arguments.
4. Recompute `agree_count`/`neutral_count`/`disagree_count`/`conviction_count` **from the
   remaining votes** (recount from scratch — safest).
5. Set the new `visibility`.
6. Notify affected users via a new FK-less notification category `hujah_archived`
   (category enum addition in `app/models/notification.rb`).

### Redirect to archive
In `HujahsController#show`: when `!@hujah.visible_to?(current_user)` **and** an
`HujahArchiveParticipant` row exists for `(current_user, @hujah)`, redirect to
`hujah_archives#show` (the frozen snapshot) instead of the normal not-authorized handling.
Old slugs continue to 301 via FriendlyId history, then hit this gate.
- Route: `get "/hoojah/:slug/archived" => "hujah_archives#show", as: :hujah_archive`
  (resolves the viewer's archive for that hujah).
- `DebateChannel` / Cable gate already re-checks `DebatePolicy#show?`; purged participants
  fail the read gate and stop receiving streams — no extra work, but add a leak spec.

### Tests
- Purge correctness: counters recomputed exactly; affected votes+leaf-args gone; unaffected
  users untouched; conviction of an affected user removed.
- Entanglement: change blocked when an affected argument has others' replies/votes/an active
  debate; unblocks after promote/delete.
- Secret ballot preserved (no `subject_user_id` leak) through the purge.
- Visibility leak: purged user redirected to archive, cannot reach live post or its Cable
  stream; still-visible users unaffected.
- Loosening never purges.
- Promote: subtree travels, becomes top-level, slug regenerates, owner-only.

---

## Slice 3 — Custom stance labels (top-level only, immutable)

### Eligibility
`User#can_customize_stances?` = `hujahs.where(parent_id: nil).not_removed.count >= 10`.
A "default hujah" for this count is a top-level, non-removed post that used the standard
labels (see storage below — a post is "custom" if any label differs from default, and custom
posts do **not** count toward the 10).

### UX (per the approved image)
On the composer's **"How people will weigh in"** preview block, for eligible users the three
words — Agree / Neutral / Disagree — are **inline click-to-edit** in place. No extra fields,
no labels, no hints, no ceremony; the affordance is discovered only by tapping a word. A small
Stimulus controller (`stance_labels_controller.js`) turns each word into an inline input on
tap and syncs the value into hidden form inputs. Ineligible users see the block unchanged and
non-editable.

### Storage — `app/models/hujah.rb` / migration
- Three nullable string columns on `hujahs`: `agree_label`, `neutral_label`, `disagree_label`.
- **Per-field** override: a user may rename any subset; each label independently custom or
  default (this supersedes the earlier "all-or-nothing" note — it fits the inline-edit UX).
- Normalisation on write: trim, collapse whitespace, 1–24 chars, no newlines; a value equal to
  its default token (case-insensitive) stores `nil` (i.e., "not customised").
- Immutable after create — never permitted in the edit/update path.
- Server drops custom labels when the author is **not** eligible (coerce to `nil`), so a
  tampered POST cannot bypass the gate.

### Rendering — `Hujah#stance_label(position)`
Returns the custom label or the default token, applied **only at this record's own** render
points: the vote bars/buttons (`_vote_bars`), the breakdown, the author's own stance badge,
and share text. **Children/replies always render default Agree/Neutral/Disagree.**
Colours and icons remain mapped to positions 1/2/3 — labels-only change, so the Tailwind
`@source inline(...)` safelist is untouched (no new classes are produced).

### Badge
Add a **`first_custom_hoojah`** badge, awarded on create when the new top-level hujah carries
any custom label. Mirror the existing badge-award path (`award_authoring_badge` /
`first_hoojah` vs `first_argument`, `hujah.rb:271, 360, 384`).

### Tests
- `can_customize_stances?` boundary at 10; custom posts excluded from the count; removed
  excluded.
- Label normalisation (trim, length cap, default-equals-token → nil); ineligible submit
  coerced to defaults.
- Immutability: update cannot change labels.
- Rendering: top-level uses custom labels at all four render points; child uses defaults.
- Badge awarded once on first custom post.

---

## Cross-cutting

- **Owner menu** (`show.html.erb`, `_card_menu`) gains "Edit" (when `body_editable?`) and, for
  top-level owners, "Change visibility".
- **Policies:** new `edit?`, `update?`, `promote?`, plus a `change_visibility?` (owner +
  top-level) guarding the visibility action.
- **Quality gates:** must stay green — `bin/ci` (StandardRB, Brakeman, bundler-audit, specs).
  Prosopite is log-only; keep the N+1 baseline from climbing in the purge/archive paths.

## Deferred / edge notes
- A user re-admitted by a later loosening and then purged again maps to their **most recent**
  archive for that hujah (participant lookup returns latest). Rare edge; acceptable.
- No un-purge / undo — the action is permanent by design.
- `allow_debates` remains editable only within the Slice-1 body-edit window (it rides the same
  form), not anytime.
