class AddMenuToKitchenEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :kitchen_events, :menu, :text
  end
end
