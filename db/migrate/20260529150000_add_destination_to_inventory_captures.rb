class AddDestinationToInventoryCaptures < ActiveRecord::Migration[8.1]
  def change
    add_column :inventory_captures, :destination, :string
  end
end
