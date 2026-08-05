class HujahPolicy < ApplicationPolicy
  # A top-level hoojah (no parent) is always allowed for a signed-in user; a reply is
  # rejected when its parent's author is hidden (blocked/blocked-by) — Slice 7.
  # Requires the controller to authorize the built instance (with parent_id), not the
  # Hujah class, so `record.parent&.user_id` is readable.
  def create? = user.present? && (record.parent_id.nil? || !user.hidden_user_ids.include?(record.parent&.user_id))

  def vote? = user.present?

  def destroy? = user.present? && record.user_id == user.id
end
