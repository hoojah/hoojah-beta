class AddUniqueIndexToUsersEmail < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!
  def change
    add_index :users, :email, unique: true, algorithm: :concurrently
  end
end
