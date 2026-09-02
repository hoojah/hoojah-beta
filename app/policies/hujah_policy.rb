class HujahPolicy < ApplicationPolicy
  # Slice 7b (Gate 5) + per-post visibility (2026): a hoojah is viewable only when
  # Hujah#visible_to? permits it — the author must be visible to the viewer AND the
  # per-post visibility must allow it. nil-safe: an anonymous viewer of a non-public
  # claim resolves to false and the ApplicationController Pundit rescue redirects.
  def show? = record.visible_to?(user)

  # A top-level hoojah (no parent) is always allowed for a signed-in user; a reply is
  # rejected when its parent's author is hidden (blocked/blocked-by) — Slice 7 — OR when
  # the parent is a private author the replier can't see — Slice 7b (Gate 10): a
  # non-follower must not write into a thread they can't read. Requires the controller
  # to authorize the built instance (with parent_id), not the Hujah class, so
  # `record.parent` is readable.
  def create?
    return false unless user.present?
    return true if record.parent_id.nil?
    parent = record.parent
    # 2026 vote-to-respond gate: you must have cast a vote on the parent before you can
    # reply to it (in addition to the Slice 7 block + Slice 7b visibility gates).
    parent && !user.hidden_user_ids.include?(parent.user_id) &&
      parent.visible_to?(user) && parent.voted_by?(user)
  end

  # Per-post visibility (2026): a viewer who can't see a claim must not be able to
  # vote on it either — voting bumps the denormalized counters and would let a stranger
  # probe existence of / interact with a non-public claim by guessing its slug.
  # Block gate (2026): mirror create?'s check — a blocker/blocked-by must not vote on
  # the author. hidden_user_ids is bidirectional (blocked OR blocked-by).
  def vote?
    user.present? && record.visible_to?(user) &&
      !user.hidden_user_ids.include?(record.user_id)
  end

  # Owner-only — AND never once a moderator has removed it. A `removed` hoojah is
  # staff-only (visible_to? hides it even from its author), and staff must be able to
  # review the removed body; letting the author hard-delete it would destroy that
  # evidence. Mirrors show?'s moderation gate — a removed hoojah is already unreachable
  # in the author's UI, so this only closes the direct-request/replay hole. (This also
  # gates the Api::V1 destroy, which shares this policy.)
  def destroy? = user.present? && record.user_id == user.id && !record.moderation_removed?

  # Slice 1 (editable hujah): the body edit surface. Owner-only, never on a
  # moderator-removed hoojah (mirrors destroy?'s evidence guard), and only while the
  # edit window is open (Hujah#body_editable? — 15 min, closed early by the first
  # conviction). Because update? repeats body_editable?, the controller's
  # `authorize @hujah` is itself the fail-closed server-side re-check for a window
  # that closes between the GET and the PATCH. nil-safe for an anonymous caller.
  def edit? = user.present? && record.user_id == user.id && !record.moderation_removed? && record.body_editable?

  def update? = edit?

  # Slice 2 (editable-hujah): visibility is changeable only by the OWNER of a TOP-LEVEL,
  # non-removed claim. Top-level only — a reply inherits its parent's visibility, so it
  # has none of its own to change. Removed mirrors destroy?: a removed claim is staff-only.
  def change_visibility? =
    user.present? && record.user_id == user.id &&
      record.parent_id.nil? && !record.moderation_removed?

  # Slice 2: promoting a reply to a standalone top-level claim is owner-only and valid
  # only on a CHILD (parent_id present) that is not removed.
  def promote? =
    user.present? && record.user_id == user.id &&
      record.parent_id.present? && !record.moderation_removed?
end
