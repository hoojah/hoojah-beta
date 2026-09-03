class AddWebauthnIdToUsers < ActiveRecord::Migration[8.1]
  # strong_migrations: adding a nullable column with no default is safe on PG.
  # A unique index on a populated table must be built CONCURRENTLY, which needs
  # the DDL transaction disabled. NULLs are distinct in a Postgres unique index,
  # so the many existing users with a NULL webauthn_id do not collide.
  disable_ddl_transaction!

  def change
    add_column :users, :webauthn_id, :string
    add_index :users, :webauthn_id, unique: true, algorithm: :concurrently
  end
end
