class CreateDebateTurns < ActiveRecord::Migration[8.1]
  def change
    create_table :debate_turns do |t|
      t.references :debate, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body
      t.integer :position, null: false
      t.timestamps
    end

    # The concurrency guard: a second turn racing to claim the same slot violates
    # this unique index (see Debate#post_turn), which serialises alternation.
    add_index :debate_turns, [:debate_id, :position], unique: true
  end
end
