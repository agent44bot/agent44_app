require "test_helper"
require "minitest/mock"

class MonthCloseInvoiceJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  def setup
    # Deliveries persist across tests in a single process, and these assertions
    # search the mailbox by subject, so start each test with an empty one.
    ActionMailer::Base.deliveries.clear
    @owner = User.create!(email_address: "owner-#{SecureRandom.hex(4)}@example.com")
    @ws = Workspace.create!(name: "NY Kitchen", slug: "nykitchen",
                            owner: @owner, timezone: "UTC",
                            base_fee_waived: true, discount_percent: 95,
                            billing_enabled: true)
  end

  test "creates an invoice for last month and emails it" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_000, output_tokens: 1_000,
                      created_at: (Date.current - 1.day).beginning_of_month + 2.days)

    assert_difference -> { Invoice.count }, 1 do
      # Two emails for a workspace with a statement roster: our invoice, then
      # the customer's usage statement.
      assert_emails 2 do
        MonthCloseInvoiceJob.new.perform
      end
    end

    inv = Invoice.last
    assert_equal (Date.current - 1.day).beginning_of_month, inv.period_start
    assert_not_nil inv.sent_at
  end

  test "explicit month arg targets that month" do
    MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))
    assert Invoice.exists?(workspace_id: @ws.id, period_start: Date.new(2026, 5, 1))
  end

  test "re-running the same month does not double-bill" do
    MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))
    assert_no_difference -> { Invoice.count } do
      MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 20))
    end
  end

  test "skips cleanly when no nykitchen workspace exists" do
    @ws.destroy
    assert_no_difference -> { Invoice.count } do
      assert_emails 0 do
        MonthCloseInvoiceJob.new.perform
      end
    end
  end

  test "delivers the invoice to the hardcoded test recipient" do
    MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))
    invoice_mail = ActionMailer::Base.deliveries.find { |m| m.subject.include?("invoice for") }
    assert_equal [ InvoiceMailer::TEST_RECIPIENT ], invoice_mail.to
  end

  test "sends the customer statement to the workspace's billing contact, cc us" do
    MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))

    statement = ActionMailer::Base.deliveries.find { |m| m.subject.include?("usage summary") }
    assert_not_nil statement, "expected a customer usage statement"
    assert_equal MonthCloseInvoiceJob::STATEMENT_RECIPIENTS["nykitchen"], statement.to
    assert_equal [ MonthCloseInvoiceJob::STATEMENT_CC ], statement.cc
    assert_no_match(/amount due/i, statement.body.to_s)
  end

  test "a Setting override replaces the statement roster" do
    Setting.set("invoice_statement.recipients.nykitchen", "someone@nykitchen.com, second@nykitchen.com")
    MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))

    statement = ActionMailer::Base.deliveries.find { |m| m.subject.include?("usage summary") }
    assert_equal %w[someone@nykitchen.com second@nykitchen.com], statement.to
  end

  test "a blank Setting override turns the statement off" do
    Setting.set("invoice_statement.recipients.nykitchen", "")
    assert_emails 1 do
      MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))
    end
  end

  test "the pause switch stops the statement but not the invoice" do
    Setting.set(MonthCloseInvoiceJob::PAUSE_KEY, "1")
    assert_emails 1 do
      MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))
    end
    assert_match(/invoice for/, ActionMailer::Base.deliveries.last.subject)
  end

  test "a failed statement does not lose the invoice or crash the run" do
    InvoiceMailer.stub(:monthly_statement, ->(*) { raise ArgumentError, "bad address" }) do
      assert_difference -> { Invoice.count }, 1 do
        MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))
      end
    end
    assert_not_nil Invoice.last.sent_at
  end

  test "a workspace with no statement roster only gets the internal invoice" do
    other = Workspace.create!(name: "Gems of Eden", slug: "gems-of-eden",
                              owner: @owner, timezone: "UTC", billing_enabled: true)
    @ws.update!(billing_enabled: false)

    assert_emails 1 do
      MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))
    end
    assert Invoice.exists?(workspace_id: other.id)
  end
  test "a rerun does not email the customer the same month twice" do
    MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))
    inv = Invoice.last
    assert_not_nil inv.statement_sent_at

    # Same month again: the invoice row is reused and only our own copy resends.
    ActionMailer::Base.deliveries.clear
    assert_emails 1 do
      MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 20))
    end
    assert_match(/invoice for/, ActionMailer::Base.deliveries.last.subject)
  end

  test "a statement that failed to send is retried on the next run" do
    InvoiceMailer.stub(:monthly_statement, ->(*) { raise ArgumentError, "bad address" }) do
      MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))
    end
    assert_nil Invoice.last.statement_sent_at, "a failed send must not stamp the invoice"

    ActionMailer::Base.deliveries.clear
    MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 20))
    statement = ActionMailer::Base.deliveries.find { |m| m.subject.include?("usage summary") }
    assert_not_nil statement
    assert_not_nil Invoice.last.statement_sent_at
  end
end
