require "test_helper"

class AgentMemoryTest < ActiveSupport::TestCase
  test "requires a body" do
    memory = agents(:ripley).agent_memories.new(title: "T", body: "")
    assert_not memory.valid?
    memory.body = "content"
    assert memory.valid?
  end

  test "display_title falls back to a humanized filename" do
    memory = AgentMemory.new(filename: "2026-04-14-team-standup.md", body: "x")
    assert_equal "2026 04 14 team standup", memory.display_title
  end

  test "recent orders newest first, tolerating missing occurred_at" do
    agent = agents(:ripley)
    older = agent.agent_memories.create!(filename: "a.md", body: "1", occurred_at: 2.days.ago)
    newer = agent.agent_memories.create!(filename: "b.md", body: "2", occurred_at: 1.hour.ago)
    assert_equal [ newer, older ], agent.agent_memories.recent.to_a
  end
end
