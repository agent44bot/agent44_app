require "test_helper"

class KitchenEventTest < ActiveSupport::TestCase
  def snapshot
    @snapshot ||= KitchenSnapshot.create!(taken_on: Date.current)
  end

  def build_event(**attrs)
    snapshot.kitchen_events.create!(
      { url: "https://nykitchen.com/event/#{SecureRandom.hex(4)}/", name: "X", start_at: 2.days.from_now }.merge(attrs)
    )
  end

  test "price_value strips formatting and parses; blank is 0" do
    assert_equal 57.0,   build_event(price: "57.00").price_value
    assert_equal 1400.0, build_event(price: "$1,400.00").price_value
    assert_equal 0.0,    build_event(price: nil).price_value
  end

  test "revenue from live capacity: sold, total, left" do
    e = build_event(price: "100.00", capacity: 10, spots_left: 4) # 6 sold, 4 left
    assert_equal 600.0,  e.revenue_sold
    assert_equal 1000.0, e.revenue_total
    assert_equal 400.0,  e.revenue_left
  end

  test "revenue is zero when capacity is unknown" do
    e = build_event(price: "100.00", capacity: nil, spots_left: nil,
                    last_known_capacity: nil, last_known_spots_left: nil)
    refute e.capacity_known?
    assert_equal 0.0, e.revenue_total
    assert_equal 0.0, e.revenue_sold
  end

  test "revenue via proxy uses the high-water mark (biased low)" do
    # No real capacity; proxy high-water of 8 seats, 5 left now → 3 sold, "8" total.
    e = build_event(price: "50.00", capacity: nil, spots_left: 5,
                    last_known_capacity: nil, last_known_spots_left: 8)
    assert e.capacity_via_proxy?
    assert_equal 150.0, e.revenue_sold   # 3 × 50
    assert_equal 400.0, e.revenue_total  # 8 × 50
    assert_equal 250.0, e.revenue_left
  end
end
