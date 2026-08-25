class AddLifecycleToFlags < ActiveRecord::Migration[8.1]
  # validate_foreign_key must run OUTSIDE the DDL transaction so it takes only a
  # SHARE ROW EXCLUSIVE lock (no write block) instead of validating while writes
  # are blocked — strong_migrations rejects the in-transaction form.
  disable_ddl_transaction!

  def up
    add_column :flags, :status, :integer, null: false, default: 0
    add_column :flags, :resolved_at, :datetime
    # index: false — resolved_by is never a lookup key; validate: false so the FK
    # add takes only a brief metadata lock, then validate separately (SHARE ROW
    # EXCLUSIVE, no write block) — the strong_migrations pattern.
    add_reference :flags, :resolved_by, index: false,
      foreign_key: {to_table: :users, validate: false}
    validate_foreign_key :flags, column: :resolved_by_id
  end

  # Explicit down: flags now carries TWO FKs to users (user_id + resolved_by_id),
  # so the auto-inverse of add_reference (remove_foreign_key by to_table: :users)
  # is ambiguous and raises. Remove by column instead.
  def down
    remove_foreign_key :flags, column: :resolved_by_id
    remove_column :flags, :resolved_by_id
    remove_column :flags, :resolved_at
    remove_column :flags, :status
  end
end
