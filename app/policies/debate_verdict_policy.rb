# frozen_string_literal: true

class DebateVerdictPolicy < ApplicationPolicy
  # A spectator may cast a verdict only on a CONCLUDED debate, only if they are
  # NOT a participant, AND only if the debate is actually visible to them (Slice
  # 7b). The show? clause closes the must-fix hole: without it a blocked user or
  # a non-follower of a private participant could POST a verdict on a debate they
  # cannot even read.
  def create?
    user.present? && record.debate.concluded? && !record.debate.participant?(user) &&
      DebatePolicy.new(user, record.debate).show?
  end
end
