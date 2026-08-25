class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    # Column-add-with-default is safe on PostgreSQL 11+ (no table rewrite).
    add_column :users, :role, :integer, null: false, default: 0
  end
end
