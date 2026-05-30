class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :invoices do |t|
      t.references :workspace, null: false, foreign_key: true
      t.date :period_start, null: false
      t.date :period_end,   null: false

      # Frozen pricing snapshot — captured at close so later rate/discount/fee
      # changes never rewrite a past invoice. All money stored as integer cents.
      t.integer :base_fee_cents,   null: false, default: 0
      t.integer :usage_cost_cents, null: false, default: 0 # raw fleet cost (AI + smoke), pre-markup
      t.decimal :multiplier,       precision: 6, scale: 2, null: false, default: "1.0"
      t.decimal :discount_percent, precision: 5, scale: 2, null: false, default: "0.0"
      t.integer :subtotal_cents,   null: false, default: 0
      t.integer :discount_cents,   null: false, default: 0
      t.integer :total_cents,      null: false, default: 0

      # Per-line breakdown (features + smoke tests) frozen at close, for the
      # email + invoice detail view. JSON array of { label, calls, cost_cents }.
      t.text :line_items

      t.string   :status, null: false, default: "unpaid" # unpaid | paid
      t.datetime :paid_at
      t.datetime :sent_at

      t.timestamps
    end

    # One invoice per workspace per billing period — guards against the
    # month-close job (or a manual re-run) double-billing a month.
    add_index :invoices, %i[workspace_id period_start], unique: true
  end
end
