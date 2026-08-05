class CreateDebateVerdicts < ActiveRecord::Migration[8.1]
  def change
    create_table :debate_verdicts do |t|
      # No standalone [debate_id] index — the composite unique index below has
      # [debate_id] as its leftmost prefix (covers the tally group-by), so the
      # auto index t.references would add is suppressed.
      t.references :debate, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.integer :choice, null: false

      t.timestamps
    end

    # One immutable verdict per spectator per debate (a real DB unique index).
    add_index :debate_verdicts, [:debate_id, :user_id], unique: true
  end
end
