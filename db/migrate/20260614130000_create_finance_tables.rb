class CreateFinanceTables < ActiveRecord::Migration[8.1]
  def change
    create_table :expenses do |t|
      t.integer :tax_year, null: false
      t.date    :incurred_on, null: false
      t.string  :vendor, null: false
      t.string  :raw_description
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string  :category
      t.text    :business_purpose
      t.string  :source, null: false, default: "manual"
      t.string  :review_flag
      t.boolean :excluded, null: false, default: false
      t.string  :fingerprint, null: false

      t.timestamps
    end
    add_index :expenses, :fingerprint, unique: true
    add_index :expenses, :tax_year

    create_table :revenue_entries do |t|
      t.integer :tax_year, null: false
      t.date    :received_on, null: false
      t.string  :source, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.text    :note

      t.timestamps
    end
    add_index :revenue_entries, :tax_year
  end
end
