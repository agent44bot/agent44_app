require "test_helper"

class KitchenSnapshotTest < ActiveSupport::TestCase
  # Build N snapshots, each one with two events whose spots_left drop by
  # `sales_per_day` each day. So `tickets_sold_today` on day N equals
  # `sales_per_day * 2` (two events, same delta each).
  def build_snapshots(days_back:, sales_per_day:)
    today = Date.current
    days_back.downto(1).each do |i|
      snap = KitchenSnapshot.create!(taken_on: today - i)
      snap.kitchen_events.create!(url: "https://nykitchen.com/a", name: "A",
                                  start_at: 1.week.from_now, spots_left: 100 - (days_back - i) * sales_per_day)
      snap.kitchen_events.create!(url: "https://nykitchen.com/b", name: "B",
                                  start_at: 1.week.from_now, spots_left: 100 - (days_back - i) * sales_per_day)
    end
  end

  test "tickets_sold_daily_avg averages across recent snapshots, excluding today" do
    build_snapshots(days_back: 5, sales_per_day: 3)

    # 5 snapshots, but the earliest has no prior to diff against → 0.
    # The other 4 each show 2 events * 3 spots dropped = 6 sold.
    # Avg = (0 + 6 + 6 + 6 + 6) / 5 = 4.8.
    assert_equal 4.8, KitchenSnapshot.tickets_sold_daily_avg
  end

  test "tickets_sold_daily_avg returns nil with fewer than 3 snapshots" do
    KitchenSnapshot.create!(taken_on: 2.days.ago.to_date)
    KitchenSnapshot.create!(taken_on: 1.day.ago.to_date)

    assert_nil KitchenSnapshot.tickets_sold_daily_avg
  end

  test "tickets_sold_daily_avg excludes today's snapshot from the average" do
    build_snapshots(days_back: 4, sales_per_day: 3)
    # Add a today snapshot with a much larger sale — should not skew the avg.
    today_snap = KitchenSnapshot.create!(taken_on: Date.current)
    today_snap.kitchen_events.create!(url: "https://nykitchen.com/a", name: "A",
                                      start_at: 1.week.from_now, spots_left: 0)
    today_snap.kitchen_events.create!(url: "https://nykitchen.com/b", name: "B",
                                      start_at: 1.week.from_now, spots_left: 0)

    # Average should still be (0 + 6 + 6 + 6) / 4 = 4.5, unaffected by today.
    assert_equal 4.5, KitchenSnapshot.tickets_sold_daily_avg
  end
end
