class BackfillFollowCounterCaches < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    users = Class.new(ActiveRecord::Base) { self.table_name = "users" }
    users.in_batches(of: 1000) do |batch|
      batch.update_all(<<~SQL)
        followers_count = (SELECT COUNT(*) FROM follows
                            WHERE follows.followed_id = users.id AND follows.status = 1),
        following_count = (SELECT COUNT(*) FROM follows
                            WHERE follows.follower_id = users.id AND follows.status = 1)
      SQL
    end
  end

  def down
    # Columns are dropped by reverting migration 1; nothing to undo here.
  end
end
