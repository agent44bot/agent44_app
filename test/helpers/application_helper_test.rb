require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # 9am / 2pm / 7pm / 1am Eastern, expressed in UTC (EDT = UTC-4 in late May).
  test "nyk_time_greeting picks the bucket by Eastern hour" do
    assert_equal "☀️ This morning:",   nyk_time_greeting(Time.utc(2026, 5, 26, 13))  #  9am EDT
    assert_equal "🌤️ This afternoon:", nyk_time_greeting(Time.utc(2026, 5, 26, 18))  #  2pm EDT
    assert_equal "🌆 This evening:",    nyk_time_greeting(Time.utc(2026, 5, 26, 23))  #  7pm EDT
    assert_equal "🌙 Tonight:",         nyk_time_greeting(Time.utc(2026, 5, 26, 5))   #  1am EDT
  end

  test "safe_internal_path accepts same-origin paths and rejects off-site ones" do
    assert_equal "/nykitchen/list", safe_internal_path("/nykitchen/list")
    assert_equal "/a?b=1",          safe_internal_path("/a?b=1")
    assert_nil safe_internal_path(nil)
    assert_nil safe_internal_path("")
    assert_nil safe_internal_path("//evil.com")      # protocol-relative
    assert_nil safe_internal_path("/\\evil.com")     # backslash host trick
    assert_nil safe_internal_path("https://evil.com")
  end
end
