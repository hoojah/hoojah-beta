class AddStatusToFollows < ActiveRecord::Migration[8.1]
  def up
    add_column :follows, :status, :integer, default: 0, null: false
    # Backfill: every follow that already exists predates the request/approve flow,
    # so it is an accepted relationship (status: 1). New follows default to pending (0)
    # and the controller sets the status explicitly per the target's privacy.
    Follow.reset_column_information
    Follow.update_all(status: 1)
  end

  def down
    remove_column :follows, :status
  end
end
