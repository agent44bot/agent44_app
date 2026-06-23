class AddPushEnabledToWorkspaceMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_memberships, :push_enabled, :boolean, default: true, null: false
  end
end
