require "test_helper"

class NykSmokeFreshnessCheckJobTest < ActiveJob::TestCase
  setup do
    Setting.delete_all
    SmokeTestRun.where("name LIKE 'nyk_%'").destroy_all
  end

  test "no alert when both kinds are fresh" do
    SmokeTestRun.create!(name: "nyk_calendar_nav_fresh", status: "passed", started_at: 30.minutes.ago, duration_ms: 30_000)
    SmokeTestRun.create!(name: "nyk_scrape_fresh",       status: "passed", started_at: 1.hour.ago,    duration_ms: 600_000)

    assert_no_difference -> { Notification.count } do
      NykSmokeFreshnessCheckJob.perform_now
    end
  end

  test "no alert when there are no runs ever (assume fresh install)" do
    assert_no_difference -> { Notification.count } do
      NykSmokeFreshnessCheckJob.perform_now
    end
  end

  test "alerts when nav is stale" do
    SmokeTestRun.create!(name: "nyk_calendar_nav_old", status: "passed", started_at: 16.hours.ago, duration_ms: 30_000)
    SmokeTestRun.create!(name: "nyk_scrape_fresh",      status: "passed", started_at: 1.hour.ago,  duration_ms: 600_000)

    assert_difference -> { Notification.count }, 1 do
      NykSmokeFreshnessCheckJob.perform_now
    end

    note = Notification.order(:created_at).last
    assert_equal "nyk_smoke", note.source
    assert_match(/nav.*stale/i, note.title)
    assert_equal "warning", note.level
  end

  test "alerts when scrape is stale" do
    SmokeTestRun.create!(name: "nyk_calendar_nav_fresh", status: "passed", started_at: 30.minutes.ago, duration_ms: 30_000)
    SmokeTestRun.create!(name: "nyk_scrape_old",          status: "passed", started_at: 8.hours.ago,    duration_ms: 600_000)

    assert_difference -> { Notification.count }, 1 do
      NykSmokeFreshnessCheckJob.perform_now
    end

    note = Notification.order(:created_at).last
    assert_match(/scrape.*stale/i, note.title)
  end

  test "alerts both when both are stale" do
    SmokeTestRun.create!(name: "nyk_calendar_nav_old", status: "passed", started_at: 16.hours.ago, duration_ms: 30_000)
    SmokeTestRun.create!(name: "nyk_scrape_old",        status: "passed", started_at: 8.hours.ago, duration_ms: 600_000)

    assert_difference -> { Notification.count }, 2 do
      NykSmokeFreshnessCheckJob.perform_now
    end
  end

  test "does not re-alert within the 6-hour cooldown" do
    SmokeTestRun.create!(name: "nyk_calendar_nav_old", status: "passed", started_at: 16.hours.ago, duration_ms: 30_000)
    Setting.set("nyk.smoke_freshness.nav.last_alert_at", 1.hour.ago.iso8601)

    assert_no_difference -> { Notification.count } do
      NykSmokeFreshnessCheckJob.perform_now
    end
  end

  test "re-alerts after the cooldown elapses" do
    SmokeTestRun.create!(name: "nyk_calendar_nav_old", status: "passed", started_at: 16.hours.ago, duration_ms: 30_000)
    Setting.set("nyk.smoke_freshness.nav.last_alert_at", 7.hours.ago.iso8601)

    assert_difference -> { Notification.count }, 1 do
      NykSmokeFreshnessCheckJob.perform_now
    end
  end
end
