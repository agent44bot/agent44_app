class InvoiceMailer < ApplicationMailer
  # Monthly invoice for a workspace's prior-month usage. TESTING: while we
  # validate the invoice flow, every invoice goes to botwhisperer@hey.com
  # regardless of workspace. Swap to the workspace's billing contact (e.g.
  # Lora on NY Kitchen) once the format is signed off.
  TEST_RECIPIENT = "botwhisperer@hey.com".freeze

  def monthly_invoice(invoice, to: TEST_RECIPIENT)
    @invoice   = invoice
    @workspace = invoice.workspace
    mail(
      to: to,
      subject: "#{@workspace.name} — invoice for #{invoice.period_label} · #{ActiveSupport::NumberHelper.number_to_currency(invoice.total_dollars)}"
    )
  end
end
