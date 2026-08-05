class AddDebateToNotifications < ActiveRecord::Migration[8.1]
  def change
    # Nullable, no FK — matches the existing loose notification style
    # (hujah_id / subject_user_id are plain nullable integers).
    add_column :notifications, :debate_id, :bigint
  end
end
