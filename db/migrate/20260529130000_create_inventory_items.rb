class CreateInventoryItems < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_items do |t|
      t.string  :name, null: false
      t.string  :category                       # wine / spirit / beer / mixer / other
      t.string  :size                           # bottle size, e.g. "750ml"
      t.string  :producer
      t.string  :vintage
      t.string  :vendor                          # where Chris orders it (from his sheet)
      # Scanning: a single-bottle UPC and an optional case/box code. Scanning the
      # case code adds units_per_case; the bottle code is one unit. SQLite treats
      # NULLs as distinct, so the unique indexes permit many un-barcoded items.
      t.string  :barcode
      t.string  :case_barcode
      t.integer :units_per_case, null: false, default: 12
      t.integer :par_level                       # reorder threshold → low-stock flag
      t.text    :notes

      t.timestamps
    end

    add_index :inventory_items, :barcode,      unique: true
    add_index :inventory_items, :case_barcode, unique: true
  end
end
