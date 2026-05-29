class CreateInventoryCaptures < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_captures do |t|
      # Who logged it. Nullify on user delete (Apple delete-account FK guard).
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.string   :category                 # wine / spirit / beer / mixer / other
      t.string   :name                      # optional free-text product name
      t.integer  :quantity,   null: false, default: 1
      t.decimal  :unit_price,  precision: 10, scale: 2  # cost each (from the seller)
      t.text     :note
      t.datetime :captured_at, null: false
      # Photo of the product is an ActiveStorage attachment (has_one_attached).

      t.timestamps
    end

    add_index :inventory_captures, :captured_at
  end
end
