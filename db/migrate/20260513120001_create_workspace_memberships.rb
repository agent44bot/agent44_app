class CreateWorkspaceMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_memberships do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user,      null: false, foreign_key: true
      t.string :role, null: false, default: "editor"
      t.datetime :last_active_at

      t.timestamps
    end

    add_index :workspace_memberships, [ :workspace_id, :user_id ], unique: true
    add_index :workspace_memberships, :role
  end
end
