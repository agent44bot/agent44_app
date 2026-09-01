# Preview at /rails/mailers/invoice_mailer/monthly_invoice
class InvoiceMailerPreview < ActionMailer::Preview
  def monthly_invoice
    InvoiceMailer.monthly_invoice(latest_invoice)
  end

  # The customer-facing usage statement (what NY Kitchen's billing contact
  # gets). Preview at /rails/mailers/invoice_mailer/monthly_statement.
  def monthly_statement
    InvoiceMailer.monthly_statement(latest_invoice,
                                    to: "billing-contact@example.com",
                                    cc: MonthCloseInvoiceJob::STATEMENT_CC)
  end

  private

  # Most recent real invoice if one exists; otherwise build last month's on the
  # fly (not saved) so the preview always renders.
  def latest_invoice
    ws = Workspace.find_by(slug: "nykitchen") || Workspace.first
    Invoice.where(workspace_id: ws&.id).recent.first ||
      Invoice.generate_for(ws, (Date.current - 1.day).beginning_of_month)
  end
end
