class BackfillUserIdentities < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    say_with_time "backfilling user_identities from users.provider/uid" do
      User.where.not(provider: [nil, ""]).where.not(uid: [nil, ""]).find_each do |u|
        UserIdentity.find_or_create_by!(provider: u.provider, uid: u.uid) do |i|
          i.user_id = u.id
        end
      end
    end
  end

  def down
    UserIdentity.delete_all
  end
end
