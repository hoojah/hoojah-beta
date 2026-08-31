# Headless policy: Pundit resolves `authorize :admin, :index?` here (mirrors
# ModerationPolicy). Purely "is this user staff" — the admin listings are read-only
# and global, so there is no per-record nuance to encode; the single `index?` gate
# reads `can_moderate?` (moderator || admin, the ONLY capability gate the rest of the
# app reads). nil-safe: an anonymous viewer resolves to false and the
# ApplicationController Pundit rescue redirects.
class AdminPolicy < ApplicationPolicy
  def index? = !!user&.can_moderate?
end
