class BackfillHujahSlugs < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    Hujah.reset_column_information
    # Existing hujahs already carry non-blank slugs from the legacy `slug` gem, so
    # they keep resolving untouched. Only BLANK slugs get (re)generated — friendly_id
    # regenerates on save when slug is blank (should_generate_new_friendly_id? is true).
    Hujah.where(slug: [nil, ""]).find_each do |h|
      h.slug = nil
      h.save!(validate: false)
    end
  end

  def down; end
end
