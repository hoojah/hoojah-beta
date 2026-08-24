class AddOpeningArgumentToDebates < ActiveRecord::Migration[8.1]
  def change
    add_column :debates, :opening_argument, :text
  end
end
