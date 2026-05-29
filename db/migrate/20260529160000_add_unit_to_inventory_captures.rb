class AddUnitToInventoryCaptures < ActiveRecord::Migration[8.1]
  def change
    add_column :inventory_captures, :unit, :string
  end
end
