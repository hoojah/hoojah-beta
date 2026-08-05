class NotificationPolicy < ApplicationPolicy
  def update? = owner?

  def destroy? = owner?

  def owner? = user.present? && record.user_id == user.id

  class Scope < ApplicationPolicy::Scope
    def resolve = user ? scope.where(user: user) : scope.none
  end
end
