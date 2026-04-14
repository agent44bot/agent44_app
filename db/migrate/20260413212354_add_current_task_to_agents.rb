class AddCurrentTaskToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :current_task, :string
  end
end
