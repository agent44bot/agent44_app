require "test_helper"
require "minitest/mock"

class AiSpendAlertJobTest < ActiveSupport::TestCase
  setup do
    @rich = User.create!(email_address: "spend-#{SecureRandom.hex(4)}@example.com", role: "admin")
    Setting.set(AiSpendAlertJob::ALERT_EMAIL, @rich.email_address)
    Setting.delete_key(AiSpendAlertJob::ALERTED_ON)
    Setting.delete_key(AiSpendAlertJob::THRESHOLD_KEY)
    Notification.delete_all
    AiCallLog.delete_all
  end

  # Opus at $5/MTok in: 1M input tokens is $5.00, so 100k is $0.50.
  def log(source, input, output = 0, at: Time.current)
    AiCallLog.create!(source: source, model: "claude-opus-4-8",
                      input_tokens: input, output_tokens: output, created_at: at)
  end

  test "stays quiet under the threshold" do
    log("nyk_recipe_extract", 100_000) # $0.50
    assert_no_difference -> { Notification.count } do
      AiSpendAlertJob.perform_now
    end
    assert_nil Setting.get(AiSpendAlertJob::ALERTED_ON)
  end

  test "pushes the alert user once the day's spend crosses a dollar" do
    log("nyk_recipe_extract", 300_000)  # $1.50
    log("nyk_social_scout",    10_000)  # $0.05

    assert_difference -> { Notification.count }, 1 do
      AiSpendAlertJob.perform_now
    end
    n = Notification.last
    assert_equal "ai_spend", n.source
    assert_equal "warning", n.level
    assert_equal @rich.id, n.user_id, "the badge belongs to the person being alerted"
    assert_equal "Anthropic spend today is $1.55", n.title
    assert_match "Over $1.00 on 2 calls.", n.body
    assert_match "nyk_recipe_extract $1.50", n.body
    assert_equal "/nykitchen/billing", n.url
  end

  test "alerts once a day, however often the job runs" do
    log("nyk_recipe_extract", 300_000)
    assert_difference -> { Notification.count }, 1 do
      3.times { AiSpendAlertJob.perform_now }
    end
    assert_equal Date.current.to_s, Setting.get(AiSpendAlertJob::ALERTED_ON)
  end

  test "yesterday's spend does not count toward today" do
    log("nyk_recipe_extract", 900_000, at: 1.day.ago) # $4.50, but not today
    log("nyk_recipe_extract",  40_000)                # $0.20 today
    assert_no_difference -> { Notification.count } do
      AiSpendAlertJob.perform_now
    end
  end

  test "yesterday's alert does not silence today's" do
    Setting.set(AiSpendAlertJob::ALERTED_ON, Date.current.yesterday.to_s)
    log("nyk_recipe_extract", 300_000)
    assert_difference -> { Notification.count }, 1 do
      AiSpendAlertJob.perform_now
    end
  end

  test "a failed alert does not spend the day's one notification" do
    log("nyk_recipe_extract", 300_000)
    Notification.stub(:notify!, nil) do
      AiSpendAlertJob.perform_now
    end
    assert_nil Setting.get(AiSpendAlertJob::ALERTED_ON), "the day is not marked done"

    # The next hourly run tries again and gets through.
    assert_difference -> { Notification.count }, 1 do
      AiSpendAlertJob.perform_now
    end
    assert_equal Date.current.to_s, Setting.get(AiSpendAlertJob::ALERTED_ON)
  end

  test "the day's window is the Eastern day, not the container's UTC day" do
    # Regression guard: prod runs with TZ=UTC and Time.zone Eastern, so a spend
    # range built from Date.current must still resolve through Time.zone.
    assert_equal Time.current.all_day.first.to_i, Date.current.all_day.first.to_i
    assert_equal(-4 * 3600, Date.current.all_day.first.utc_offset, "Eastern, not UTC")
  end

  test "the threshold is settable, and a junk value falls back to the default" do
    Setting.set(AiSpendAlertJob::THRESHOLD_KEY, "5")
    log("nyk_recipe_extract", 400_000) # $2.00, under the raised bar
    assert_no_difference -> { Notification.count } do
      AiSpendAlertJob.perform_now
    end

    Setting.set(AiSpendAlertJob::THRESHOLD_KEY, "not a number")
    assert_difference -> { Notification.count }, 1 do
      AiSpendAlertJob.perform_now
    end
    assert_match "Over $1.00", Notification.last.body
  end

  test "the body names the biggest sources and sums the tail" do
    log("nyk_recipe_extract", 200_000) # $1.00
    log("nyk_recipe_generate", 60_000) # $0.30
    log("nyk_grocery_list",    40_000) # $0.20
    log("nyk_social_scout",     6_000) # $0.03
    log("nyk_team_report",      4_000) # $0.02
    AiSpendAlertJob.perform_now

    body = Notification.last.body
    assert_match "nyk_recipe_extract $1.00", body
    assert_match "nyk_recipe_generate $0.30", body
    assert_match "nyk_grocery_list $0.20", body
    assert_match "2 others $0.05", body
    assert_no_match(/nyk_social_scout/, body, "the tail is summed, not listed")
  end
end
