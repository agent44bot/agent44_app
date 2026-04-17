class AddCostCentsToSmokeTestRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :smoke_test_runs, :cost_cents, :integer, default: 1, null: false
  end
end
