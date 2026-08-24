class CreateHashtagHujahs < ActiveRecord::Migration[8.1]
  def change
    create_table :hashtag_hujahs do |t|
      t.references :hashtag, null: false, foreign_key: true
      t.references :hujah, null: false, foreign_key: true
      t.timestamps
    end
    add_index :hashtag_hujahs, [:hashtag_id, :hujah_id], unique: true
  end
end
