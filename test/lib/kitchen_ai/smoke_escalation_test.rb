require "test_helper"

class KitchenAi::SmokeEscalationTest < ActiveSupport::TestCase
  def nav(status, at)    = SmokeTestRun.create!(name: "nyk_calendar_nav", status: status, started_at: at)
  def scrape(status, at) = SmokeTestRun.create!(name: "nyk_scrape",       status: status, started_at: at)

  teardown { Setting.delete_key("nyk_developer_email"); Setting.delete_key("super_agent_daily_prompt_email") }

  test "streak counts consecutive most-recent failed nav runs" do
    nav("passed", 5.hours.ago)
    nav("failed", 4.hours.ago)
    nav("failed", 3.hours.ago)
    nav("failed", 2.hours.ago)
    assert_equal 3, KitchenAi::SmokeEscalation.streak
    assert KitchenAi::SmokeEscalation.alerting?
  end

  test "a pass resets the streak" do
    nav("failed", 3.hours.ago)
    nav("failed", 2.hours.ago)
    nav("passed", 1.hour.ago)
    assert_equal 0, KitchenAi::SmokeEscalation.streak
    refute KitchenAi::SmokeEscalation.alerting?
  end

  test "scrape failures and in-flight runs do not count toward the nav streak" do
    nav("failed", 3.hours.ago)
    nav("failed", 2.hours.ago)
    nav("failed", 1.hour.ago)
    scrape("failed", 30.minutes.ago)  # different test
    nav("running", 1.minute.ago)      # not finished
    assert_equal 3, KitchenAi::SmokeEscalation.streak
  end

  test "draft prompt is triage-first, names the count and the developer email" do
    3.times { |i| nav("failed", (3 - i).hours.ago) }
    Setting.set("nyk_developer_email", "dev@nykitchen.com")

    q = KitchenAi::SmokeEscalation.draft_prompt
    assert_match "3 times in a row", q
    assert_match "dev@nykitchen.com", q
    assert_match(/do not send it/i, q)
  end

  test "draft prompt falls back to a generic recipient when no email is set" do
    3.times { |i| nav("failed", (3 - i).hours.ago) }
    assert_match "the developer", KitchenAi::SmokeEscalation.draft_prompt
  end

  test "trial_user resolves from the shared daily-prompt setting" do
    u = User.create!(email_address: "rb-#{SecureRandom.hex(3)}@example.com", role: "admin")
    Setting.set("super_agent_daily_prompt_email", u.email_address)
    assert_equal u, KitchenAi::SmokeEscalation.trial_user
  end
end
