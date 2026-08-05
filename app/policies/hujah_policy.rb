class HujahPolicy < ApplicationPolicy
  def create? = user.present?

  def vote? = user.present?

  def destroy? = user.present? && record.user_id == user.id
end
