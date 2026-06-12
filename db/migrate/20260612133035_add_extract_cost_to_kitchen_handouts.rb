class AddExtractCostToKitchenHandouts < ActiveRecord::Migration[8.1]
  def change
    add_column :kitchen_handouts, :extract_cost_cents, :integer
  end
end
