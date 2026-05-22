class AddSettingsToWorkspaceAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_agents, :settings, :json, null: false, default: {}
  end
end
