class Hashtag < ApplicationRecord
  has_many :hashtag_hujahs, dependent: :destroy
  has_many :hujahs, through: :hashtag_hujahs
  validates :name, presence: true, uniqueness: true

  # Canonical lookup key: a tag is addressed and stored lower-cased, so #KlangValley
  # and #klangvalley collapse to one row. `display` keeps the first-seen casing.
  def self.canonical(raw) = raw.to_s.downcase
end
