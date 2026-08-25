# Headless policy: Pundit resolves `authorize :moderation, :<action>?` here.
# Purely "is this user staff" — there is no per-record nuance to encode, so all four
# actions share the same gate (`can_moderate?` = moderator || admin, the ONLY capability
# gate the rest of the app reads). nil-safe: an anonymous viewer resolves to false and
# the ApplicationController Pundit rescue redirects.
class ModerationPolicy < ApplicationPolicy
  def index? = !!user&.can_moderate?

  def dismiss? = !!user&.can_moderate?

  def remove? = !!user&.can_moderate?

  def warn? = !!user&.can_moderate?
end
