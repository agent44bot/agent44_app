class MonthCloseInvoiceJob < ApplicationJob
  queue_as :default

  # Runs on the 1st of the month: freezes last month's NY Kitchen usage into an
  # Invoice row and emails it. Generation is idempotent (unique index on
  # workspace+period), so a re-run on the same month reuses the existing row
  # rather than double-billing.
  def perform(month: nil)
    workspace = Workspace.find_by(slug: "nykitchen")
    unless workspace
      Rails.logger.info("MonthCloseInvoiceJob: no nykitchen workspace, skipping")
      return
    end

    # Default target = the calendar month that just ended (yesterday's month).
    target = month || (Date.current - 1.day).beginning_of_month
    invoice = Invoice.generate_for(workspace, target)
    deliver(invoice)
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
  end
end
