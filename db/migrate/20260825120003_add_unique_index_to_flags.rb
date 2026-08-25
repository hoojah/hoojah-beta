class AddUniqueIndexToFlags < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Dedup before the unique index: keep the EARLIEST flag per [user, hujah]
    # (beta data — no known duplicates, but the migration must not assume that).
    # safety_assured: a bounded one-time data fix on a tiny table; strong_migrations
    # blocks raw execute by default and this is the sanctioned escape hatch.
    safety_assured do
      execute <<~SQL
        DELETE FROM flags a USING flags b
        WHERE a.user_id = b.user_id AND a.hujah_id = b.hujah_id AND a.id > b.id
      SQL
    end
    add_index :flags, [:user_id, :hujah_id], unique: true,
      name: "index_flags_on_user_and_hujah", algorithm: :concurrently
  end

  def down
    remove_index :flags, name: "index_flags_on_user_and_hujah"
  end
end
