require "test_helper"

class MonthCloseInvoiceJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  def setup
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
      assert_emails 1 do
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

  test "delivers to the hardcoded test recipient" do
    MonthCloseInvoiceJob.new.perform(month: Date.new(2026, 5, 15))
    assert_equal [ InvoiceMailer::TEST_RECIPIENT ], ActionMailer::Base.deliveries.last.to
  end
end
