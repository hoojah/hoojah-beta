# frozen_string_literal: true

# Owner-only management of a WebAuthn credential. index/options/create are handled
# by controller-level current_user scoping (skip_authorization), so only the
# mutating-a-specific-record actions need a policy.
class PasskeyPolicy < ApplicationPolicy
  def update? = record.user_id == user&.id

  def destroy? = record.user_id == user&.id
end
