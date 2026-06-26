class AddShowGroceryPricesToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :show_grocery_prices, :boolean, default: false, null: false
  end
end
