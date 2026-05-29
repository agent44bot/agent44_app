class CreateInventoryMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_movements do |t|
      t.references :inventory_item, null: false, foreign_key: { on_delete: :cascade }
      # Who scanned it (Lora in, Chris out). Nullify on user delete so the
      # Apple-required Delete-account flow isn't blocked by this FK.
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.string   :direction, null: false        # "in" (received) / "out" (drawn down)
      t.integer  :quantity,  null: false, default: 1
      t.string   :scanned_code                   # the raw barcode actually scanned
      t.text     :note
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :inventory_movements, :occurred_at
    add_index :inventory_movements, [ :inventory_item_id, :occurred_at ]
  end
end
