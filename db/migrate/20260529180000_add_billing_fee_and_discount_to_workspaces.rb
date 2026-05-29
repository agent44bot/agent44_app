class AddBillingFeeAndDiscountToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    # Per-workspace customer pricing, set by the site admin on the billing page.
    add_column :workspaces, :base_fee_dollars, :decimal, precision: 10, scale: 2 # flat monthly fee; null -> app default
    add_column :workspaces, :base_fee_waived,  :boolean, default: false, null: false
    add_column :workspaces, :discount_percent, :decimal, precision: 5, scale: 2, default: 0 # % off the customer total
  end
end
