class AddBodyEditedAtToHujahs < ActiveRecord::Migration[8.1]
  def change
    add_column :hujahs, :body_edited_at, :datetime
  end
end
