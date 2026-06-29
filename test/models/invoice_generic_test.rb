require "test_helper"

# Invoice generation for a generic (non-NYK) workspace: bills its own
# workspace-attributed AI usage with the workspace's usage_multiplier, no smoke
# tests, generic line-item labels.
class InvoiceGenericTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "ig-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "Gen WS", owner: @owner, usage_multiplier: 2.0)
    @other = Workspace.create!(name: "Other WS", owner: @owner)
  end

  def log(ws, input:, output:, model: "claude-haiku-4-5-20251001")
    AiCallLog.create!(workspace: ws, source: "workspace_ai_assist", model: model, input_tokens: input, output_tokens: output)
  end

  test "generate_for bills the workspace's own usage with its multiplier, no smoke" do
    # Haiku: 1M in * $1 + 1M out * $5 = $6.00 raw.
    log(@ws, input: 1_000_000, output: 1_000_000)
    # A different workspace's usage must NOT be counted.
    log(@other, input: 5_000_000, output: 5_000_000, model: "claude-opus-4-8")

    invoice = Invoice.generate_for(@ws, Date.current)

    assert_in_delta 6.0, invoice.usage_cost_dollars, 0.001, "only this workspace's raw cost"
    assert_equal 2.0, invoice.multiplier.to_f
    assert_in_delta 12.0, invoice.total_dollars, 0.001, "raw x multiplier, no base fee"

    labels = invoice.line_items.map { |li| li["label"] }
    assert_includes labels, "Social Agent drafts"
    refute_includes labels, "Browser smoke tests"
  end

  test "generate_for is idempotent per workspace + month" do
    log(@ws, input: 1000, output: 500)
    first  = Invoice.generate_for(@ws, Date.current)
    second = Invoice.generate_for(@ws, Date.current)
    assert_equal first.id, second.id
  end
end
