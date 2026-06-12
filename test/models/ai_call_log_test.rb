require "test_helper"

class AiCallLogTest < ActiveSupport::TestCase
  test "cost_dollars uses haiku 4.5 published rates ($1/MTok in, $5/MTok out)" do
    log = AiCallLog.new(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                        input_tokens: 1_500, output_tokens: 800)
    expected = (1_500 * 1.00 / 1_000_000.0) + (800 * 5.00 / 1_000_000.0)
    assert_in_delta expected, log.cost_dollars, 1e-9
  end

  test "cost_dollars uses opus 4.8 published rates ($5/MTok in, $25/MTok out)" do
    log = AiCallLog.new(model: "claude-opus-4-8", input_tokens: 1_000_000, output_tokens: 1_000_000)
    assert_in_delta 30.00, log.cost_dollars, 0.0001
  end

  test "nyk scope includes recipe extraction" do
    AiCallLog.create!(model: "claude-opus-4-8", source: "nyk_recipe_extract", input_tokens: 1, output_tokens: 1)
    assert_includes AiCallLog.nyk.pluck(:source), "nyk_recipe_extract"
  end

  test "cost_dollars falls back to default rate for unknown model" do
    log = AiCallLog.new(model: "claude-future-9000", source: "nyk_enhance",
                        input_tokens: 1_000_000, output_tokens: 0)
    assert_in_delta 1.0, log.cost_dollars, 1e-9
  end

  test "cost_cents is cost_dollars * 100" do
    log = AiCallLog.new(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                        input_tokens: 100_000, output_tokens: 0)
    assert_in_delta 10.0, log.cost_cents, 1e-9
  end

  test "nyk scope returns only NYK_SOURCES" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance", input_tokens: 1, output_tokens: 1)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_x_autopost", input_tokens: 1, output_tokens: 1)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "other_feature", input_tokens: 1, output_tokens: 1)

    assert_equal 2, AiCallLog.nyk.count
    assert AiCallLog.nyk.pluck(:source).all? { |s| AiCallLog::NYK_SOURCES.include?(s) }
  end

  test "this_month scope excludes rows from prior months" do
    log_old   = AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                                  input_tokens: 1, output_tokens: 1, created_at: 60.days.ago)
    log_fresh = AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                                  input_tokens: 1, output_tokens: 1)

    ids = AiCallLog.this_month.pluck(:id)
    assert_includes     ids, log_fresh.id
    assert_not_includes ids, log_old.id
  end

  test "summary_by_source aggregates calls + tokens + cost per source" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_500, output_tokens: 800)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 500, output_tokens: 200)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_x_autopost",
                      input_tokens: 300, output_tokens: 100)

    summary = AiCallLog.summary_by_source(AiCallLog.all)
    assert_equal 2, summary["nyk_enhance"][:calls]
    assert_equal 2_000, summary["nyk_enhance"][:input_tokens]
    assert_equal 1_000, summary["nyk_enhance"][:output_tokens]
    assert_in_delta 0.007, summary["nyk_enhance"][:cost_dollars], 1e-9

    assert_equal 1, summary["nyk_x_autopost"][:calls]
    assert_in_delta 0.0008, summary["nyk_x_autopost"][:cost_dollars], 1e-9
  end

  test "total_cost_dollars sums across the given relation" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_000_000, output_tokens: 0)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_x_autopost",
                      input_tokens: 0, output_tokens: 200_000)

    assert_in_delta 2.0, AiCallLog.total_cost_dollars(AiCallLog.all), 1e-9
    assert_in_delta 1.0, AiCallLog.total_cost_dollars(AiCallLog.where(source: "nyk_enhance")), 1e-9
  end

  test "super_agent scope returns only the chat sources" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_ask",     input_tokens: 1, output_tokens: 1)
    AiCallLog.create!(model: "claude-haiku-4-5",          source: "nyk_agent",   input_tokens: 1, output_tokens: 1)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance", input_tokens: 1, output_tokens: 1)

    assert_equal 2, AiCallLog.super_agent.count
    assert AiCallLog.super_agent.pluck(:source).all? { |s| AiCallLog::SUPER_AGENT_SOURCES.include?(s) }
  end

  test "usage_rollup aggregates calls/tokens/cost in one query" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_ask",   input_tokens: 1_500, output_tokens: 800)
    AiCallLog.create!(model: "claude-haiku-4-5",          source: "nyk_agent", input_tokens:   500, output_tokens: 200)

    roll = AiCallLog.usage_rollup(AiCallLog.super_agent)
    assert_equal 2,     roll[:calls]
    assert_equal 2_000, roll[:input_tokens]
    assert_equal 1_000, roll[:output_tokens]
    assert_equal 3_000, roll[:total_tokens]
    # (2000 * $1 + 1000 * $5) / 1e6 = $0.007
    assert_in_delta 0.007, roll[:cost_dollars], 1e-9
  end

  test "usage_rollup on an empty scope returns zeros, not nil" do
    roll = AiCallLog.usage_rollup(AiCallLog.where(source: "does_not_exist"))
    assert_equal 0,   roll[:calls]
    assert_equal 0,   roll[:total_tokens]
    assert_in_delta 0.0, roll[:cost_dollars], 1e-9
  end
end
