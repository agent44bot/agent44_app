require "test_helper"

# Covers the run lifecycle that backs the NYK hub presence dots:
#   create as "running" (no ended_at) → patch to "passed"/"failed".
# Also covers the .finished scope used by the hub to find the most
# recent terminal row when an in-flight row is at the top of .recent.
class SmokeTestRunTest < ActiveSupport::TestCase
  test "can be created in running status with no ended_at" do
    run = SmokeTestRun.create!(name: "nyk_calendar_nav_lifecycle", status: "running", started_at: Time.current)
    assert run.running?
    refute run.passed?
    refute run.failed?
    assert_nil run.ended_at
  end

  test "can be patched from running to passed" do
    run = SmokeTestRun.create!(name: "nyk_calendar_nav_lifecycle", status: "running", started_at: 30.seconds.ago)
    run.update!(status: "passed", ended_at: Time.current, duration_ms: 30_000)
    assert run.passed?
    refute run.running?
    assert run.ended_at.present?
    assert run.cost_dollars.positive?, "cost should auto-compute from duration_ms"
  end

  test ".finished excludes running rows" do
    SmokeTestRun.where("name LIKE ?", "nyk_calendar_nav_scope%").destroy_all
    SmokeTestRun.create!(name: "nyk_calendar_nav_scope1", status: "passed",  started_at: 2.hours.ago, ended_at: 2.hours.ago + 30, duration_ms: 30_000)
    SmokeTestRun.create!(name: "nyk_calendar_nav_scope2", status: "running", started_at: 1.minute.ago)

    all_names      = SmokeTestRun.where("name LIKE ?", "nyk_calendar_nav_scope%").pluck(:name).sort
    finished_names = SmokeTestRun.where("name LIKE ?", "nyk_calendar_nav_scope%").finished.pluck(:name).sort
    assert_equal %w[nyk_calendar_nav_scope1 nyk_calendar_nav_scope2], all_names
    assert_equal %w[nyk_calendar_nav_scope1], finished_names
  end

  test "rejects unknown status" do
    assert_raises ActiveRecord::RecordInvalid do
      SmokeTestRun.create!(name: "nyk_calendar_nav_bad", status: "queued", started_at: Time.current)
    end
  end

  test "window_stats rolls up pass/fail for a scope over a date window" do
    SmokeTestRun.create!(name: "nyk_calendar_nav", status: "passed", started_at: 3.days.ago, ended_at: 3.days.ago + 30, duration_ms: 30_000)
    SmokeTestRun.create!(name: "nyk_calendar_nav", status: "passed", started_at: 2.days.ago, ended_at: 2.days.ago + 30, duration_ms: 30_000)
    SmokeTestRun.create!(name: "nyk_calendar_nav", status: "failed", started_at: 1.day.ago,  ended_at: 1.day.ago + 30,  duration_ms: 30_000)
    SmokeTestRun.create!(name: "nyk_calendar_nav", status: "running", started_at: 1.minute.ago) # excluded (not finished)
    SmokeTestRun.create!(name: "nyk_calendar_nav", status: "passed", started_at: 30.days.ago, ended_at: 30.days.ago + 30, duration_ms: 30_000) # outside window

    stats = SmokeTestRun.window_stats(:nyk_nav, Date.current - 7, Date.current)
    assert_equal 3, stats[:total]   # the 3 finished in-window
    assert_equal 2, stats[:passed]
    assert_equal 1, stats[:failed]
    assert_equal 33, stats[:fail_pct]
  end
end
