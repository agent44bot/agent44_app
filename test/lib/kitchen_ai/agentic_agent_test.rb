require "test_helper"

# Unit tests for the read-tools-only AgenticAgent (v1). The Anthropic call is
# fully replaced via the class.stub seam — nothing reaches the real API, per the
# project rule "No AI enhance in tests".
class KitchenAi::AgenticAgentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup    { ENV["ANTHROPIC_API_KEY"] = "test-key" }
  teardown do
    ENV.delete("ANTHROPIC_API_KEY")
    KitchenAi::AgenticAgent.stub = nil
  end

  test "loop runs a read tool, feeds the result back, and ends" do
    calls = 0
    fed_back = nil
    KitchenAi::AgenticAgent.stub = lambda do |model:, max_tokens:, system:, messages:, tools:|
      calls += 1
      if calls == 1
        { "stop_reason" => "tool_use",
          "content" => [{ "type" => "tool_use", "id" => "tu_1",
                          "name" => "list_classes", "input" => { "filter" => "upcoming" } }] }
      else
        fed_back = messages.last
        { "stop_reason" => "end_turn",
          "content" => [{ "type" => "text", "text" => "Here you go." }] }
      end
    end

    res = KitchenAi::AgenticAgent.new(user: nil).run([{ role: "user", content: "what's on?" }])

    assert res.ok?, res.error
    assert_equal 2, calls
    assert_equal 2, res.steps
    assert_equal "Here you go.", res.reply
    # the turn after the tool call must be a user turn carrying the tool_result
    assert_equal "user", fed_back[:role]
    assert_equal "tool_result", fed_back[:content].first[:type]
    assert_equal "tu_1", fed_back[:content].first[:tool_use_id]
  end

  test "v1 is read-only: no write tools even for an owner" do
    agent = KitchenAi::AgenticAgent.new(user: nil, workspace_role: "owner") # enable_writes defaults false
    names = agent.send(:tool_definitions).map { |d| d[:name] }
    assert_equal %w[get_fleet_status list_classes get_sales_summary], names
    refute names.include?("trigger_scrape")
  end

  test "write tools require BOTH enable_writes and an owner/admin role" do
    viewer = KitchenAi::AgenticAgent.new(user: nil, workspace_role: "viewer", enable_writes: true)
    refute viewer.send(:tool_definitions).map { |d| d[:name] }.include?("trigger_scrape")

    admin = KitchenAi::AgenticAgent.new(user: nil, workspace_role: "owner", enable_writes: true)
    assert admin.send(:tool_definitions).map { |d| d[:name] }.include?("trigger_scrape")
  end

  test "executing a write tool in read-only mode is refused, not run" do
    agent = KitchenAi::AgenticAgent.new(user: nil, workspace_role: "owner") # read-only
    # If the gate failed this would enqueue a real job; assert it does not.
    assert_no_enqueued_jobs do
      text, is_error = agent.send(:execute, "trigger_scrape", {})
      assert is_error
      assert_match(/disabled in this mode/, text)
    end
  end

  test "system prompt and tool list carry cache_control breakpoints" do
    agent = KitchenAi::AgenticAgent.new(user: nil)
    assert agent.send(:cached_system).last[:cache_control].present?
    assert agent.send(:tool_definitions).last[:cache_control].present?
  end
end
