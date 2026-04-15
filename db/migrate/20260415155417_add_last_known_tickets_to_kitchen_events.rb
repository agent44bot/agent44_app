class AddLastKnownTicketsToKitchenEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :kitchen_events, :last_known_spots_left, :integer
    add_column :kitchen_events, :last_known_capacity, :integer
  end
end
