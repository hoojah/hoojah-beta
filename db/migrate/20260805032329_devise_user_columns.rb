class DeviseUserColumns < ActiveRecord::Migration[8.1]
  def change
    safety_assured { rename_column :users, :password_digest, :encrypted_password }
    change_column_default :users, :encrypted_password, from: nil, to: ""
    safety_assured { change_column_null :users, :encrypted_password, false, "" }

    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime
    add_column :users, :remember_created_at, :datetime
    safety_assured { add_index :users, :reset_password_token, unique: true }

    # normalize existing emails to lowercase so the unique index + Devise agree
    up_only { safety_assured { execute "UPDATE users SET email = lower(email)" } }
    change_column_default :users, :email, from: nil, to: ""
  end
end
