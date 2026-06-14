class CreateGroceryReceipts < ActiveRecord::Migration[8.1]
  def change
    create_table :grocery_receipts do |t|
      t.date    :purchased_on
      t.date    :week_start
      t.date    :week_end
      t.string  :store
      t.integer :total_cents
      t.text    :notes
      t.string  :status, null: false, default: "pending" # pending, parsed, failed
      t.text    :parse_error
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end

    # The accumulating price history: one observed unit price per receipt line.
    # Queried when building future grocery estimates so they use real numbers
    # instead of guesses.
    create_table :ingredient_prices do |t|
      t.string  :canonical_name, null: false
      t.string  :unit
      t.integer :unit_price_cents, null: false
      t.decimal :quantity, precision: 10, scale: 2
      t.string  :raw_label
      t.date    :observed_on, null: false
      t.references :grocery_receipt, foreign_key: true, null: true
      t.timestamps
    end
    add_index :ingredient_prices, [ :canonical_name, :observed_on ]
  end
end
