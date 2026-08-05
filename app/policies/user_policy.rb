class UserPolicy < ApplicationPolicy
  def update? = user.present? && record.id == user.id
end
