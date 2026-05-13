class CreateWorkspaceInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_invitations do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.string  :email, null: false
      t.string  :role,  null: false, default: "editor"
      t.string  :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at
      t.references :accepted_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :workspace_invitations, :token, unique: true
    add_index :workspace_invitations, [:workspace_id, :email]
    add_index :workspace_invitations, :expires_at
  end
end
