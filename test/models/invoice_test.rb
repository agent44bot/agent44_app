require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  def setup
    @owner = User.create!(email_address: "owner-#{SecureRandom.hex(4)}@example.com")
    @ws = Workspace.create!(name: "NY Kitchen", slug: "nyk-#{SecureRandom.hex(4)}",
                            owner: @owner, timezone: "UTC",
                            base_fee_waived: true, discount_percent: 95)
    @month = Date.new(2026, 5, 15)
  end

  test "generate_for builds a frozen invoice for the calendar month" do
    # 1M in @ $1/MTok + 1M out @ $5/MTok = $6.00 raw AI. (No smoke run here:
    # SmokeTestRun#compute_cost recomputes cost_dollars from the workspace
    # rate keyed on the "nykitchen" slug, which this random-slug test ws lacks,
    # so a smoke row's cost would collapse to the tiny fallback. Smoke
    # inclusion is covered in the line_items test instead.)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_000_000, output_tokens: 1_000_000,
                      created_at: Time.zone.local(2026, 5, 10))

    inv = Invoice.generate_for(@ws, @month)

    assert_equal Date.new(2026, 5, 1),  inv.period_start
    assert_equal Date.new(2026, 5, 31), inv.period_end
    assert_equal "unpaid", inv.status
    assert_in_delta 6.00, inv.usage_cost_dollars, 0.001
    assert_equal 3.0, inv.multiplier.to_f
    assert_equal 0,   inv.base_fee_cents # waived
    # subtotal = 6.00 * 3 = 18.00; 95% off -> 0.90
    assert_in_delta 18.00, inv.subtotal_dollars, 0.01
    assert_in_delta 0.90,  inv.total_dollars, 0.01
  end

  test "generate_for excludes usage outside the period" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_000_000, output_tokens: 0,
                      created_at: Time.zone.local(2026, 4, 30, 23, 59)) # April
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_000_000, output_tokens: 0,
                      created_at: Time.zone.local(2026, 6, 1, 0, 1)) # June

    inv = Invoice.generate_for(@ws, @month)
    assert_equal 0, inv.usage_cost_cents, "April + June usage must not bleed into May"
  end

  test "generate_for is idempotent per workspace+period" do
    inv1 = Invoice.generate_for(@ws, Date.new(2026, 5, 1))
    inv2 = Invoice.generate_for(@ws, Date.new(2026, 5, 28))
    assert_equal inv1.id, inv2.id
    assert_equal 1, Invoice.where(workspace_id: @ws.id).count
  end

  test "frozen snapshot does not change when workspace pricing changes later" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_000_000, output_tokens: 0,
                      created_at: Time.zone.local(2026, 5, 10))
    inv = Invoice.generate_for(@ws, @month)
    frozen_total = inv.total_cents

    @ws.update!(discount_percent: 0, base_fee_waived: false, base_fee_dollars: 50)
    assert_equal frozen_total, inv.reload.total_cents, "existing invoice must not recompute"
  end

  test "mark_paid! flips status and stamps paid_at" do
    inv = Invoice.generate_for(@ws, @month)
    assert_not inv.paid?
    inv.mark_paid!
    assert inv.paid?
    assert_not_nil inv.paid_at
  end

  test "line_items captures per-feature breakdown plus smoke tests" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_x_autopost",
                      input_tokens: 100, output_tokens: 100,
                      created_at: Time.zone.local(2026, 5, 5))
    SmokeTestRun.create!(name: "nyk_scrape", status: "passed",
                         started_at: Time.zone.local(2026, 5, 6),
                         duration_ms: 60_000, cost_dollars: 0.044)
    inv = Invoice.generate_for(@ws, @month)
    labels = inv.line_items.map { |li| li["label"] }
    assert_includes labels, "Daily X autopost draft"
    assert_includes labels, "Browser smoke tests"
  end
end
