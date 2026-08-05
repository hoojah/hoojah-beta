class AddPrivateToUsers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :users, :private, :boolean, default: false, null: false
    add_index :users, :private, algorithm: :concurrently
  end
end
