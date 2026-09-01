class AddStatementSentAtToInvoices < ActiveRecord::Migration[8.1]
  # Stamped when the customer-facing usage statement goes out, so a rerun or
  # retry of MonthCloseInvoiceJob cannot email the customer the same month
  # twice. The existing `sent_at` covers only the internal invoice.
  def change
    add_column :invoices, :statement_sent_at, :datetime
  end
end
