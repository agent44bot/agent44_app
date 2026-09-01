require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  def setup
    @owner = User.create!(email_address: "owner-#{SecureRandom.hex(4)}@example.com")
    # slug "nykitchen" so generate_for takes the NYK billing branch (NYK_SOURCES
    # + smoke tests + ENV multiplier), which is what these assertions cover.
    @ws = Workspace.create!(name: "NY Kitchen", slug: "nykitchen",
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
    assert_equal 0,   inv.base_fee_cents # applied = 0 (waived)
    assert inv.base_fee_waived?
    assert_equal 5000, inv.base_fee_configured_cents # pre-waive $50 frozen for strike-through
    # subtotal = 6.00 * 3 = 18.00; 95% off -> 0.90
    assert_in_delta 18.00, inv.subtotal_dollars, 0.01
    assert_in_delta 0.90,  inv.total_dollars, 0.01
  end

  test "non-waived workspace freezes the applied fee and is not marked waived" do
    @ws.update!(base_fee_waived: false, base_fee_dollars: 40, discount_percent: 0)
    inv = Invoice.generate_for(@ws, @month)
    assert_not inv.base_fee_waived?
    assert_equal 4000, inv.base_fee_cents
    assert_equal 4000, inv.base_fee_configured_cents
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
  # --- Customer statement figures -------------------------------------------

  test "list price prices the month as if nothing were waived or discounted" do
    @ws.update!(base_fee_dollars: 50, base_fee_waived: true, discount_percent: 95)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_000_000, output_tokens: 0,
                      created_at: Date.new(2026, 5, 10))

    inv = Invoice.generate_for(@ws, Date.new(2026, 5, 1))

    # $1.00 of raw usage at the NYK 3x markup, plus the $50 fee it is not paying.
    assert_in_delta 53.0, inv.list_price_dollars, 0.01
    assert_in_delta 0.15, inv.total_dollars, 0.01
    assert_in_delta 52.85, inv.pilot_credit_dollars, 0.01
  end

  test "pilot credit never goes negative" do
    @ws.update!(base_fee_dollars: 0, base_fee_waived: false, discount_percent: 0)
    inv = Invoice.generate_for(@ws, Date.new(2026, 5, 1))
    inv.update!(total_cents: inv.total_cents + 5_000)

    assert_equal 0.0, inv.pilot_credit_dollars
  end

  test "average list price smooths across the trailing months" do
    ws = @ws
    [ [ Date.new(2026, 3, 1), 30_00 ], [ Date.new(2026, 4, 1), 60_00 ], [ Date.new(2026, 5, 1), 90_00 ] ].each do |start, cents|
      Invoice.create!(workspace: ws, period_start: start, period_end: start.end_of_month,
                      usage_cost_cents: cents, multiplier: 1.0, status: "unpaid")
    end

    latest = Invoice.where(workspace_id: ws.id).order(:period_start).last
    assert_in_delta 60.0, latest.average_list_price_dollars, 0.01

    middle = Invoice.where(workspace_id: ws.id).order(:period_start).second
    assert_in_delta 45.0, middle.average_list_price_dollars, 0.01, "should ignore months after the invoice"
  end
  test "NYK AI work we absorb is frozen onto the invoice at no charge" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_000_000, output_tokens: 0,
                      created_at: Date.new(2026, 5, 10))
    # Echo's listening: run for them, absorbed by us, shown at $0.
    2.times do
      AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_social_scout",
                        input_tokens: 500_000, output_tokens: 0,
                        created_at: Date.new(2026, 5, 11))
    end
    # Our own admin dogfood agent: not theirs, must not appear at all.
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_agent",
                      input_tokens: 900_000, output_tokens: 0,
                      created_at: Date.new(2026, 5, 12))

    inv = Invoice.generate_for(@ws, Date.new(2026, 5, 1))

    billed = inv.billed_line_items.map { |li| li["label"] }
    assert_equal [ "Enhance with AI button" ], billed

    free = inv.unbilled_line_items
    assert_equal [ "Echo social listening" ], free.map { |li| li["label"] },
                 "nyk_agent is our admin dogfood traffic and must never reach the customer"
    assert_equal 2, free.first["calls"]
    assert_equal 0, free.first["cost_cents"]

    # The absorbed line must not reach the money: $1.00 of billed usage only.
    assert_in_delta 1.00, inv.usage_cost_dollars, 0.001
    assert_in_delta 1.00, inv.metered_usage_dollars, 0.001
  end

  test "line helpers price each item and its per-use rate" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 40_000, output_tokens: 0,
                      created_at: Date.new(2026, 5, 10))

    inv  = Invoice.generate_for(@ws, Date.new(2026, 5, 1))
    line = inv.billed_line_items.first

    # 40k input tokens at $1/MTok = $0.04, over one call.
    assert_in_delta 0.04, Invoice.line_cost_dollars(line), 0.0001
    assert_in_delta 0.04, Invoice.line_unit_dollars(line), 0.0001
    assert_equal 4, line["cost_cents"], "rounded cents stay on the row for the internal invoice"
  end

  test "line cost falls back to rounded cents on rows written before full precision" do
    legacy = { "label" => "Browser smoke tests", "calls" => 4, "cost_cents" => 250 }

    assert_in_delta 2.50, Invoice.line_cost_dollars(legacy), 0.0001
    assert_in_delta 0.625, Invoice.line_unit_dollars(legacy), 0.0001
  end

  test "a zero-volume line does not divide by zero" do
    assert_equal 0.0, Invoice.line_unit_dollars({ "calls" => 0, "cost_dollars" => 0.0 })
  end
end
