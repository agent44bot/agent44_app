class CreateSocialAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :social_accounts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :connected_by, foreign_key: { to_table: :users }
      t.string :platform, null: false
      t.string :handle
      t.string :display_name
      t.string :avatar_url
      t.string :external_id
      t.text   :access_token
      t.text   :refresh_token
      t.text   :token_secret
      t.datetime :token_expires_at
      t.text   :scopes
      t.string :status, null: false, default: "active"
      t.datetime :last_synced_at
      t.text :metadata

      t.timestamps
    end

    add_index :social_accounts, [ :workspace_id, :platform, :external_id ], unique: true, name: "idx_social_accts_on_ws_platform_extid"
    add_index :social_accounts, :status
  end
end
