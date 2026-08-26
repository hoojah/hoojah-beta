class AddUniqueIndexToFlags < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Dedup before the unique index: keep the EARLIEST flag per [user, hujah]
    # (beta data — no known duplicates, but the migration must not assume that).
    dedup = <<~SQL
      DELETE FROM flags a USING flags b
      WHERE a.user_id = b.user_id AND a.hujah_id = b.hujah_id AND a.id > b.id
    SQL

    # strong_migrations blocks raw `execute` and offers `safety_assured` as the sanctioned
    # escape hatch — but it is a dev/test-only gem, so `safety_assured` is UNDEFINED in
    # production. Guard on it: wrap when present (dev/test), run plainly when absent (prod,
    # where nothing blocks execute). Without this guard the migration raised
    # `NoMethodError: undefined method 'safety_assured'` on the production deploy
    # (2026-08-26), after the three preceding migrations had already applied.
    if respond_to?(:safety_assured)
      safety_assured { execute(dedup) }
    else
      execute(dedup)
    end

    add_index :flags, [:user_id, :hujah_id], unique: true,
      name: "index_flags_on_user_and_hujah", algorithm: :concurrently
  end

  def down
    remove_index :flags, name: "index_flags_on_user_and_hujah"
  end
end
