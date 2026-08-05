class DebateTurn < ApplicationRecord
  belongs_to :debate
  belongs_to :user

  validates :body, presence: true
end
