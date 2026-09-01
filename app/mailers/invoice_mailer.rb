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

  # The customer-facing twin of monthly_invoice: same frozen invoice row, read
  # as a usage statement rather than a bill. It leads with what the fleet did
  # (site checks, AI actions), then prices the month at list and shows the
  # pilot credit, because its job is to give the customer a number they can put
  # in next year's budget. No "amount due", no payment ask.
  def monthly_statement(invoice, to:, cc: nil)
    @invoice   = invoice
    @workspace = invoice.workspace
    mail(
      to: to,
      cc: cc.presence,
      subject: "#{@workspace.name}: Agent44 usage summary for #{invoice.period_label}"
    )
  end
end
