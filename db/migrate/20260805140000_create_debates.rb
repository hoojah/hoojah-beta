class CreateDebates < ActiveRecord::Migration[8.1]
  def change
    create_table :debates do |t|
      t.references :hujah, null: false, foreign_key: true
      t.references :challenger, null: false, foreign_key: {to_table: :users}
      t.references :opponent, null: false, foreign_key: {to_table: :users}
      t.integer :challenger_stance, null: false
      t.integer :opponent_stance, null: false
      t.integer :status, null: false
      t.string :slug, null: false
      t.timestamps
    end

    add_index :debates, :slug, unique: true
    # One live (pending/active) debate per (hoojah, challenger, opponent) triple.
    # The partial predicate lets a concluded/declined pair re-challenge later.
    safety_assured do
      add_index :debates, [:hujah_id, :challenger_id, :opponent_id],
        unique: true, where: "status IN (0,1)", name: "no_dup_live_debate"
    end
  end
end
