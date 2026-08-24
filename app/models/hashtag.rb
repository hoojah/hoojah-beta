class Hashtag < ApplicationRecord
  has_many :hashtag_hujahs, dependent: :destroy
  has_many :hujahs, through: :hashtag_hujahs
  validates :name, presence: true, uniqueness: true

  # Full-text search (Phase 2.2). Hashtags carry no privacy of their own, so no
  # visible_to reuse is needed here (unlike Hujah.search / User.search). `?` bind
  # PLUS `sanitize_sql_like` on the term — the bind alone stops SQL injection but
  # not the user's own `%`/`_` being read as a wildcard.
  scope :search, ->(q) { where("name ILIKE ?", "%#{sanitize_sql_like(q)}%").order(hujahs_count: :desc).limit(8) }

  # Canonical lookup key: a tag is addressed and stored lower-cased, so #KlangValley
  # and #klangvalley collapse to one row. `display` keeps the first-seen casing.
  def self.canonical(raw) = raw.to_s.downcase
end
