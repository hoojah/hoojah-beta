class HujahPolicy < ApplicationPolicy
  # Slice 7b (Gate 5): a hoojah is viewable only when its author is visible to the
  # viewer (public author → everyone incl. anonymous; private author → self + accepted
  # followers). nil-safe: an anonymous viewer of a private author resolves to false and
  # the ApplicationController Pundit rescue redirects.
  def show? = record.user.visible_to?(user)

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
    parent && !user.hidden_user_ids.include?(parent.user_id) && parent.visible_to?(user)
  end

  def vote? = user.present?

  def destroy? = user.present? && record.user_id == user.id
end
