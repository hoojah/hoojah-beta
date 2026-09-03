class CreateWebauthnCredentials < ActiveRecord::Migration[8.1]
  # New (empty) table, so inline index creation is safe — no concurrent build needed.
  def change
    create_table :webauthn_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false   # credential id from the authenticator (base64url)
      t.string :public_key, null: false    # COSE public key (base64url)
      t.string :nickname, null: false      # user-facing label
      t.bigint :sign_count, null: false, default: 0 # clone-detection counter
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :webauthn_credentials, :external_id, unique: true
    add_index :webauthn_credentials, [:user_id, :nickname], unique: true
  end
end
