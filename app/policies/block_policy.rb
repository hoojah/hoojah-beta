# frozen_string_literal: true

class BlockPolicy < ApplicationPolicy
  def create? = user.present?

  def destroy? = record.blocker_id == user&.id
end
