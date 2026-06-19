class AddAutoToKitchenHandoutLinks < ActiveRecord::Migration[8.1]
  def change
    add_column :kitchen_handout_links, :auto, :boolean, default: false, null: false
  end
end
