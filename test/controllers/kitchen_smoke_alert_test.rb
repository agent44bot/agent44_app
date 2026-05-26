require "test_helper"

# The hub Super Agent card: the always-on pulse dot, and the smoke-failure
# alert that (for the trial user) preempts the morning question.
class KitchenSmokeAlertTest < ActionDispatch::IntegrationTest
  def fail_nav_runs(n)
    n.times { |i| SmokeTestRun.create!(name: "nyk_calendar_nav", status: "failed", started_at: (n - i).hours.ago) }
  end

  teardown { Setting.delete_key("super_agent_daily_prompt_email") }

  test "always-on green pulse dot renders on the Super Agent card" do
    sign_in_as(User.create!(email_address: "u-#{SecureRandom.hex(3)}@example.com", role: "admin"))
    get "/nykitchen"
    assert_response :success
    assert_match "Always on — ask anytime", @response.body
  end

  test "trial user sees the smoke alert (over the morning question) when failing repeatedly" do
    fail_nav_runs(3)
    user = User.create!(email_address: "rb-#{SecureRandom.hex(3)}@example.com", role: "admin")
    Setting.set("super_agent_daily_prompt_email", user.email_address)
    sign_in_as(user)

    get "/nykitchen"
    assert_response :success
    assert_match "failed 3 times in a row", @response.body
    assert_match(/\/nykitchen\/ask\?[^"']*q=/, @response.body)
    assert_match "go=1", @response.body
    assert_no_match "This morning:", @response.body
  end

  test "non-trial user never sees the smoke alert" do
    fail_nav_runs(3)
    Setting.set("super_agent_daily_prompt_email", "someone-else@example.com")
    sign_in_as(User.create!(email_address: "other-#{SecureRandom.hex(3)}@example.com", role: "admin"))

    get "/nykitchen"
    assert_response :success
    assert_no_match "failed 3 times in a row", @response.body
  end
end
