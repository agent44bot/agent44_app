class AddLlmModelToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :llm_model, :string
    add_column :agents, :schedule, :string
  end
end
