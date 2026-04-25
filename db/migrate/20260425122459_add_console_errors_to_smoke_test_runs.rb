class AddConsoleErrorsToSmokeTestRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :smoke_test_runs, :console_errors, :text
  end
end
