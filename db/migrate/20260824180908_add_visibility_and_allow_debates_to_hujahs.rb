class AddVisibilityAndAllowDebatesToHujahs < ActiveRecord::Migration[8.1]
  def change
    add_column :hujahs, :visibility, :integer, null: false, default: 0
    add_column :hujahs, :allow_debates, :boolean, null: false, default: true
    add_column :hujahs, :conviction_count, :integer, null: false, default: 0
  end
end
