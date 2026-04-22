class AddImageUrlToKitchenEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :kitchen_events, :image_url, :string
  end
end
