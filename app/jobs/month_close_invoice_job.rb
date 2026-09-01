class MonthCloseInvoiceJob < ApplicationJob
  queue_as :default

  # Workspaces whose billing contact also gets the customer-facing usage
  # statement (InvoiceMailer#monthly_statement), keyed by slug. The internal
  # invoice still goes to us either way. Overridable at runtime without a
  # deploy via Setting "invoice_statement.recipients.<slug>" (comma separated),
  # and an empty override turns the statement off for that workspace.
  STATEMENT_RECIPIENTS = {
    "nykitchen" => %w[lora.downie@nykitchen.com]
  }.freeze

  # Everyone on our side who gets cc'd on a customer statement.
  STATEMENT_CC = "botwhisperer@hey.com".freeze

  # Kill switch for the customer statement (the internal invoice is unaffected):
  #   Setting.set("invoice_statement.paused", "1")   # stop sending
  #   Setting.delete_key("invoice_statement.paused") # resume
  PAUSE_KEY = "invoice_statement.paused".freeze

  # Runs on the 1st of the month: freezes last month's NY Kitchen usage into an
  # Invoice row and emails it. Generation is idempotent (unique index on
  # workspace+period), so a re-run on the same month reuses the existing row
  # rather than double-billing.
  def perform(month: nil)
    workspaces = Workspace.where(billing_enabled: true).to_a
    if workspaces.empty?
      Rails.logger.info("MonthCloseInvoiceJob: no billing-enabled workspaces, skipping")
      return
    end

    # Default target = the calendar month that just ended (yesterday's month).
    target = month || (Date.current - 1.day).beginning_of_month
    workspaces.each do |workspace|
      invoice = Invoice.generate_for(workspace, target)
      deliver(invoice)
    end
  rescue => e
    Notification.notify!(
      level: "error",
      source: "nyk_billing",
      title: "MonthCloseInvoiceJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end

  # Send the invoice email and stamp sent_at. Extracted so a one-off test send
  # (MonthCloseInvoiceJob.new.deliver(invoice)) hits the exact same content as
  # the scheduled run. Recipient is hardcoded to the test address in the mailer
  # for now.
  def deliver(invoice)
    InvoiceMailer.monthly_invoice(invoice).deliver_now
    invoice.update!(sent_at: Time.current)
    Rails.logger.info("MonthCloseInvoiceJob: sent invoice ##{invoice.id} for #{invoice.period_label} (total #{invoice.total_dollars})")
    deliver_statement(invoice)
  end

  # Customer-facing usage statement. Sent after the invoice and deliberately in
  # its own begin/rescue: a bad customer address must not stop the run or lose
  # the invoice we already sent ourselves.
  def deliver_statement(invoice)
    return if Setting.get(PAUSE_KEY).present?

    recipients = statement_recipients(invoice.workspace)
    return if recipients.empty?

    InvoiceMailer.monthly_statement(invoice, to: recipients, cc: STATEMENT_CC).deliver_now
    Rails.logger.info("MonthCloseInvoiceJob: sent statement for invoice ##{invoice.id} to #{recipients.join(', ')}")
  rescue => e
    Rails.logger.error("MonthCloseInvoiceJob: statement for invoice ##{invoice.id} failed: #{e.class}: #{e.message}")
    Notification.notify!(
      level: "warning",
      source: "nyk_billing",
      title: "Customer usage statement failed to send",
      body: "Invoice ##{invoice.id} (#{invoice.workspace.name}, #{invoice.period_label}): #{e.class}: #{e.message}",
      telegram: true
    )
  end

  # Setting override first (comma separated, blank means "off"), else the
  # hardcoded roster.
  def statement_recipients(workspace)
    override = Setting.get("invoice_statement.recipients.#{workspace.slug}")
    list = override.nil? ? STATEMENT_RECIPIENTS[workspace.slug] : override.split(",")
    Array(list).map(&:strip).reject(&:blank?)
  end
end
