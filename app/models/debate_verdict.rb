class DebateVerdict < ApplicationRecord
  belongs_to :debate
  belongs_to :user

  enum :choice, {challenger: 0, opponent: 1, draw: 2}
end
