class FlagPolicy < ApplicationPolicy
  def create? = user.present?
end
