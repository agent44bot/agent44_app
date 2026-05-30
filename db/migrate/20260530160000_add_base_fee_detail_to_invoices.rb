class AddBaseFeeDetailToInvoices < ActiveRecord::Migration[8.0]
  def change
    # Freeze the pre-waive fee + waived flag so the invoice can render
    # "$50.00 Waived" (struck through) like the billing page. base_fee_cents
    # stays the *applied* fee (0 when waived) used in the pricing math.
    add_column :invoices, :base_fee_configured_cents, :integer, null: false, default: 0
    add_column :invoices, :base_fee_waived, :boolean, null: false, default: false
  end
end
