class ReplaceCostCentsWithCostDollarsOnSmokeTestRuns < ActiveRecord::Migration[8.1]
  def up
    add_column :smoke_test_runs, :cost_dollars, :decimal, precision: 10, scale: 6, default: 0.0, null: false

    # Convert existing cost_cents to dollars
    execute "UPDATE smoke_test_runs SET cost_dollars = cost_cents / 100.0"

    remove_column :smoke_test_runs, :cost_cents
  end

  def down
    add_column :smoke_test_runs, :cost_cents, :integer, default: 1, null: false
    execute "UPDATE smoke_test_runs SET cost_cents = CAST(cost_dollars * 100 AS INTEGER)"
    remove_column :smoke_test_runs, :cost_dollars
  end
end
