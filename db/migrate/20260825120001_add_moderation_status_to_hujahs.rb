class AddModerationStatusToHujahs < ActiveRecord::Migration[8.1]
  def change
    add_column :hujahs, :moderation_status, :integer, null: false, default: 0
  end
end
