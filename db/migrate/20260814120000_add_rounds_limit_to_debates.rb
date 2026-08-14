class AddRoundsLimitToDebates < ActiveRecord::Migration[8.1]
  # Extracted to a constant so the spec can exercise the exact SQL that ships
  # here, rather than a hand-copied paraphrase that could drift from it.
  #
  # A blanket `default: 4` would put already-long ACTIVE debates at or past
  # their cap and auto-conclude them on their next turn. Debate#current_round is
  # `(turns.count / 2) + 1`, so `current_round + 1` is `count / 2 + 2` — every
  # active debate lands strictly above the round it is currently on. The
  # GREATEST floor of 4 covers short debates (counts 0..3, where `count / 2 + 2`
  # is only 2 or 3) and keeps them at the product default.
  #
  # Postgres integer division truncates toward zero (COUNT(*) is bigint, `/ 2`
  # is integer division, not a rounding numeric divide), which is exactly what
  # Ruby's Integer#/ does in current_round — the two stay in step at odd counts.
  #
  # status 1 == :active — an integer literal so this migration never couples to
  # the enum (verified against Debate's `enum :status` at time of writing).
  BACKFILL_SQL = <<~SQL
    UPDATE debates SET rounds_limit = GREATEST(
      4,
      (SELECT COUNT(*) FROM debate_turns WHERE debate_turns.debate_id = debates.id) / 2 + 2
    ) WHERE status = 1
  SQL

  def up
    add_column :debates, :rounds_limit, :integer, null: false, default: 4
    # Strong Migrations cannot see inside `execute`, so it needs an explicit
    # assurance. Safe here: one bounded UPDATE over `debates` (a small table at
    # this stage) inside the migration's own transaction, so the new column and
    # its backfill land atomically. If `debates` ever grows large enough for the
    # ACCESS EXCLUSIVE lock to matter, split this into a separate batched
    # data migration.
    safety_assured { execute BACKFILL_SQL }
  end

  def down
    remove_column :debates, :rounds_limit
  end
end
