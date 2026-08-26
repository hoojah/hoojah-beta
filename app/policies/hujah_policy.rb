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

  def destroy? = user.present? && record.user_id == user.id
end
