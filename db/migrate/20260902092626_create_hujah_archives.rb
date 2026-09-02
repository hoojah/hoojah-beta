class CreateHujahArchives < ActiveRecord::Migration[8.1]
  def change
    create_table :hujah_archives do |t|
      # Integer, NO foreign key: the archive is a permanent record that must OUTLIVE
      # the live hoojah (mirrors notifications.hujah_id). A cascading FK would erase the
      # frozen evidence the purged user is entitled to read.
      t.integer :hujah_id, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.integer :visibility_before, null: false
      t.string :token, null: false

      t.timestamps
    end

    add_index :hujah_archives, :hujah_id
    add_index :hujah_archives, :token, unique: true
  end
end
