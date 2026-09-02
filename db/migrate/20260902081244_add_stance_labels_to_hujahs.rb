class AddStanceLabelsToHujahs < ActiveRecord::Migration[8.1]
  def change
    add_column :hujahs, :agree_label, :string
    add_column :hujahs, :neutral_label, :string
    add_column :hujahs, :disagree_label, :string
  end
end
