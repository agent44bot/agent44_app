require "test_helper"

class WorkspacesHelperTest < ActionView::TestCase
  TZ = "Eastern Time (US & Canada)".freeze

  test "labels today and yesterday relative to the workspace timezone" do
    now = Time.current.in_time_zone(TZ)
    assert_equal "Today",     social_post_day_label(now, TZ)
    assert_equal "Yesterday", social_post_day_label(now - 1.day, TZ)
  end

  test "older dates show the month and day, with year only for prior years" do
    now = Time.current.in_time_zone(TZ)
    older = now - 3.days
    assert_equal older.strftime("%b %-d"), social_post_day_label(older, TZ)

    last_year = now - 1.year
    assert_equal last_year.strftime("%b %-d, %Y"), social_post_day_label(last_year, TZ)
  end
end
