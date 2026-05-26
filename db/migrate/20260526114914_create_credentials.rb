class CreateCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :external_id, null: false # WebAuthn credential ID (base64url)
      t.string   :public_key,  null: false
      t.bigint   :sign_count,  null: false, default: 0
      t.string   :nickname
      t.datetime :last_used_at

      t.timestamps
    end
    add_index :credentials, :external_id, unique: true

    # Stable per-user WebAuthn handle (the user.id in the ceremony), generated
    # lazily on first passkey registration.
    add_column :users, :webauthn_id, :string
    add_index  :users, :webauthn_id, unique: true
  end
end
