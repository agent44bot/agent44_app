class AddSourceToKitchenHandouts < ActiveRecord::Migration[8.1]
  def change
    add_column :kitchen_handouts, :source_url, :string
    add_column :kitchen_handouts, :source_kind, :string
  end
end
