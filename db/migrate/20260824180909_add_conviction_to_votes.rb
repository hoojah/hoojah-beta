class AddConvictionToVotes < ActiveRecord::Migration[8.1]
  def change
    add_column :votes, :conviction, :boolean, null: false, default: false
  end
end
