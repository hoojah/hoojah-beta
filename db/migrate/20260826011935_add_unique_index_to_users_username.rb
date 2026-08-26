class AddUniqueIndexToUsersUsername < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :users, :username, unique: true, algorithm: :concurrently
  end
end
