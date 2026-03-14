class AddNostrFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pubkey_hex, :string
    add_column :users, :npub, :string
    add_column :users, :display_name, :string
    add_column :users, :role, :string, default: "member"
    add_index :users, :pubkey_hex, unique: true
    add_index :users, :npub, unique: true
  end
end
