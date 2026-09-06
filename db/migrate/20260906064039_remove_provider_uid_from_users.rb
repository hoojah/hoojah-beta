class RemoveProviderUidFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, column: [:provider, :uid], unique: true, if_exists: true
    safety_assured do
      remove_column :users, :provider, :string
      remove_column :users, :uid, :string
    end
  end
end
