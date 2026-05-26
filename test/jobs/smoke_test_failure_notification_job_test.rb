require "test_helper"

class SmokeTestFailureNotificationJobTest < ActiveJob::TestCase
  def nav(status, at) = SmokeTestRun.create!(name: "nyk_calendar_nav", status: status, started_at: at)

  setup do
    @user = User.create!(email_address: "rb-#{SecureRandom.hex(3)}@example.com", role: "admin")
    Setting.set("super_agent_daily_prompt_email", @user.email_address)
  end
  teardown do
    Setting.delete_key("super_agent_daily_prompt_email")
    Setting.delete_key("smoke_streak_incident")
  end

  def escalations = Notification.where(source: "smoke_streak_escalation")

  test "escalates once when the nav streak crosses the threshold, deep-linked to auto-ask" do
    nav("failed", 3.hours.ago)
    nav("failed", 2.hours.ago)
    last = nav("failed", 1.hour.ago)

    assert_difference -> { escalations.count }, 1 do
      SmokeTestFailureNotificationJob.perform_now(last.id)
    end

    note = escalations.last
    assert_equal @user.id, note.user_id
    assert_match "/nykitchen/ask", note.url
    assert_match "go=1", note.url
  end

  test "does not re-escalate the same incident on a later failure or a retry" do
    nav("failed", 3.hours.ago)
    nav("failed", 2.hours.ago)
    last = nav("failed", 1.hour.ago)
    SmokeTestFailureNotificationJob.perform_now(last.id)

    SmokeTestFailureNotificationJob.perform_now(last.id)        # retry of the same run
    more = nav("failed", 30.minutes.ago)                        # streak grows to 4

    assert_no_difference -> { escalations.count } do
      SmokeTestFailureNotificationJob.perform_now(more.id)
    end
  end

  test "below the threshold it does not escalate" do
    nav("failed", 2.hours.ago)
    last = nav("failed", 1.hour.ago)
    assert_no_difference -> { escalations.count } do
      SmokeTestFailureNotificationJob.perform_now(last.id)
    end
  end

  test "a scrape failure does not trigger the nav escalation" do
    nav("failed", 3.hours.ago)
    nav("failed", 2.hours.ago)
    nav("failed", 1.hour.ago)
    scrape = SmokeTestRun.create!(name: "nyk_scrape", status: "failed", started_at: 30.minutes.ago)
    assert_no_difference -> { escalations.count } do
      SmokeTestFailureNotificationJob.perform_now(scrape.id)
    end
  end
end
