class CreateWorkspaceAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_agents do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :kind,         null: false
      t.integer :agent_number, null: false
      t.string :display_name
      t.timestamps
    end
    add_index :workspace_agents, [ :workspace_id, :kind ],         unique: true
    add_index :workspace_agents, [ :workspace_id, :agent_number ], unique: true
  end
end
