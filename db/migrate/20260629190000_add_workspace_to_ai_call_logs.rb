class AddWorkspaceToAiCallLogs < ActiveRecord::Migration[8.1]
  def change
    add_reference :ai_call_logs, :workspace, null: true, index: true
  end
end
