# Preview at /rails/mailers/invoice_mailer/monthly_invoice
class InvoiceMailerPreview < ActionMailer::Preview
  def monthly_invoice
    ws = Workspace.find_by(slug: "nykitchen") || Workspace.first
    # Use the most recent real invoice if one exists; otherwise build last
    # month's on the fly (not saved) so the preview always renders.
    invoice = Invoice.where(workspace_id: ws&.id).recent.first ||
              Invoice.generate_for(ws, (Date.current - 1.day).beginning_of_month)
    InvoiceMailer.monthly_invoice(invoice)
  end
end
