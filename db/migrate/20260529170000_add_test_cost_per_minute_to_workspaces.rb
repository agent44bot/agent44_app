class AddTestCostPerMinuteToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    # Per-workspace $/min rate for browser smoke/test runs. Null → app default
    # (SmokeTestRun::COST_PER_MINUTE). Set by the site admin on the billing page.
    add_column :workspaces, :test_cost_per_minute, :decimal, precision: 12, scale: 6
  end
end
