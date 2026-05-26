require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # 9am / 2pm / 7pm / 1am Eastern, expressed in UTC (EDT = UTC-4 in late May).
  test "nyk_time_greeting picks the bucket by Eastern hour" do
    assert_equal "☀️ This morning:",   nyk_time_greeting(Time.utc(2026, 5, 26, 13))  #  9am EDT
    assert_equal "🌤️ This afternoon:", nyk_time_greeting(Time.utc(2026, 5, 26, 18))  #  2pm EDT
    assert_equal "🌆 This evening:",    nyk_time_greeting(Time.utc(2026, 5, 26, 23))  #  7pm EDT
    assert_equal "🌙 Tonight:",         nyk_time_greeting(Time.utc(2026, 5, 26, 5))   #  1am EDT
  end
end
