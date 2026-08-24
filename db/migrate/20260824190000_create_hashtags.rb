class CreateHashtags < ActiveRecord::Migration[8.1]
  def change
    create_table :hashtags do |t|
      t.string :name, null: false            # canonical, lower-cased
      t.string :display, null: false         # first-seen original casing, for chips
      t.integer :hujahs_count, null: false, default: 0
      t.timestamps
    end
    add_index :hashtags, :name, unique: true
  end
end
