class AddDailyDigestEnabledToWorkspaceMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_memberships, :daily_digest_enabled, :boolean, default: true, null: false
  end
end
