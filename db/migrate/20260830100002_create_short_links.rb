class CreateShortLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :short_links do |t|
      t.string :code, null: false
      t.string :target_path, null: false

      t.timestamps
    end

    add_index :short_links, :code, unique: true
    add_index :short_links, :target_path, unique: true
  end
end
