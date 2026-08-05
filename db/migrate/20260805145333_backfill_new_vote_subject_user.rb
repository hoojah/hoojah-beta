class BackfillNewVoteSubjectUser < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Data-only remediation for existing rows: null the leaked first-voter id on
  # every new_vote notification. Uses the enum's integer value (4 = new_vote) to
  # avoid coupling the migration to the model constant.
  def up = Notification.where(category: 4).update_all(subject_user_id: nil)

  def down
  end
end
