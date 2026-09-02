class CreateHujahArchiveParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :hujah_archive_participants do |t|
      t.bigint :archive_id, null: false
      t.bigint :user_id, null: false

      t.timestamps
    end

    add_index :hujah_archive_participants, :archive_id
    # One row per (archive, user): a user is mapped to a given archive at most once.
    add_index :hujah_archive_participants, [:archive_id, :user_id], unique: true
  end
end
