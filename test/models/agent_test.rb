require "test_helper"

class AgentTest < ActiveSupport::TestCase
  test "ordered scope puts busy agents first" do
    agents(:russ).update!(status: "busy", current_task: "Scanning", last_active_at: Time.current)

    ordered = Agent.ordered.pluck(:name)
    assert_equal "Russ 🔒", ordered.first, "Busy agent should be first"
  end

  test "ordered scope puts error agents above online" do
    agents(:vlad).update!(status: "error", current_task: "Tests failed", last_active_at: Time.current)

    ordered = Agent.ordered.pluck(:name)
    assert_equal "Vlad ✅", ordered.first, "Error agent should be first"
  end

  test "busy agents sort above error agents" do
    agents(:russ).update!(status: "busy", current_task: "Scanning", last_active_at: Time.current)
    agents(:vlad).update!(status: "error", current_task: "Failed", last_active_at: Time.current)

    ordered = Agent.ordered.pluck(:name)
    assert_equal "Russ 🔒", ordered.first, "Busy should be above error"
    assert_equal "Vlad ✅", ordered.second, "Error should be second"
  end

  test "recently active agents sort above inactive when all online" do
    agents(:scout).update!(status: "online", last_active_at: 1.minute.ago)
    agents(:ripley).update!(status: "online", last_active_at: 10.minutes.ago)
    agents(:neo).update!(status: "online", last_active_at: nil)

    ordered = Agent.ordered.pluck(:name)
    scout_idx = ordered.index("Scout 🔭")
    ripley_idx = ordered.index("Ripley")
    neo_idx = ordered.index("Neo 💻")

    assert scout_idx < ripley_idx, "More recently active should be higher"
    assert ripley_idx < neo_idx, "Active should be above never-active"
  end

  test "busy agent jumps to top regardless of position" do
    # Scout is position 7 (last), but when busy should be first
    agents(:scout).update!(status: "busy", current_task: "Researching", last_active_at: Time.current)

    ordered = Agent.ordered.pluck(:name)
    assert_equal "Scout 🔭", ordered.first, "Busy agent should jump to top regardless of position"
  end

  test "agent returns to activity-based position after going back online" do
    # Make Scout busy then online with recent last_active_at
    agents(:scout).update!(status: "busy", current_task: "Working", last_active_at: Time.current)
    agents(:scout).update!(status: "online")

    ordered = Agent.ordered.pluck(:name)
    assert_equal "Scout 🔭", ordered.first, "Recently active agent should stay near top"
  end

  test "status_label returns current_task when busy" do
    agent = agents(:russ)
    agent.update!(status: "busy", current_task: "Security scanning fitcorn")
    assert_equal "Security scanning fitcorn", agent.status_label
  end

  test "status_label returns default when busy with no task" do
    agent = agents(:russ)
    agent.update!(status: "busy", current_task: nil)
    assert_equal "Working on a task", agent.status_label
  end

  test "status_label returns capitalized status when online" do
    agent = agents(:russ)
    assert_equal "Online", agent.status_label
  end

  test "error is a valid status" do
    agent = agents(:russ)
    agent.update!(status: "error", current_task: "Scan failed")
    assert agent.valid?
    assert agent.error?
    assert_equal "red", agent.status_color
  end
end
