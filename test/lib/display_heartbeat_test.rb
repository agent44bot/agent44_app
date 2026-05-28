require "test_helper"

class DisplayHeartbeatTest < ActiveSupport::TestCase
  test "no records yet → zero days seen, nil tracking_since" do
    assert_equal 0, DisplayHeartbeat.days_seen(since: Date.current - 6)
    assert_nil DisplayHeartbeat.tracking_since
  end

  test "record! logs distinct days; days_seen respects the window" do
    DisplayHeartbeat.record!(Date.current)
    DisplayHeartbeat.record!(Date.current)      # idempotent — same day
    DisplayHeartbeat.record!(Date.current - 2)
    DisplayHeartbeat.record!(Date.current - 10) # outside a 7-day window

    assert_equal 2, DisplayHeartbeat.days_seen(since: Date.current - 6) # today + (today-2)
    assert_equal Date.current - 10, DisplayHeartbeat.tracking_since
  end
end
