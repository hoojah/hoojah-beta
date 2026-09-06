class AddImageColumnsToHujahs < ActiveRecord::Migration[8.1]
  def change
    add_column :hujahs, :image_alt, :string
    add_column :hujahs, :image_removed_at, :datetime
  end
end
