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

  test "truly_sold_out? and sales_ended? distinguish a sellout from a sales cutoff" do
    soldout = build_event(availability: "SoldOut")
    closed  = build_event(availability: "Closed")   # "Tickets no longer available"
    instock = build_event(availability: "InStock")

    assert soldout.truly_sold_out?
    refute soldout.sales_ended?
    refute closed.truly_sold_out?
    assert closed.sales_ended?
    refute instock.truly_sold_out?
    refute instock.sales_ended?

    # sold_out? (unbookable) still covers both, for the list/display.
    assert soldout.sold_out?
    assert closed.sold_out?
    refute instock.sold_out?
  end

  test "private_event? flags private bookings/buyouts by name" do
    assert build_event(name: "Hands-On Kitchen Classroom Reserved for Private Event").private_event?
    assert build_event(name: "WNYHeroes Private Chef's Table 8/28/26").private_event?
    refute build_event(name: "Homemade Fresh Pasta Workshop 7/5/26").private_event?
    # word boundary: "Privateer"-style substrings shouldn't match
    refute build_event(name: "Privateer Rum Tasting").private_event?
  end

  test "people_per_ticket defaults to 1 and stays 1 for a single-person ticket" do
    e = build_event(description: "For this class, 1 ticket is for 1 person.")
    assert_nil e.detected_people_per_ticket
    assert_equal 1, e.people_per_ticket
  end

  test "people_per_ticket auto-detects 2 from couples / two-person wording" do
    [ "Each ticket portion is for two people, so bring a friend.",
      "One ticket admits two guests.",
      "A couples cooking class, perfect for date night.",
      "Hands on dinner for two people." ].each do |text|
      e = build_event(description: text)
      assert_equal 2, e.detected_people_per_ticket, text.inspect
      assert_equal 2, e.people_per_ticket, text.inspect
    end
  end

  test "manual override wins over auto-detect and survives by url, not row" do
    couples = build_event(description: "A couples class for two people.")
    Setting.set("#{KitchenEvent::PORTION_OVERRIDE_PREFIX}#{couples.url}", 1)
    assert_equal 1, couples.people_per_ticket, "override forces 1 over a detected 2"
    assert couples.portion_overridden?

    single = build_event(description: "Solo seats.")
    Setting.set("#{KitchenEvent::PORTION_OVERRIDE_PREFIX}#{single.url}", 2)
    assert_equal 2, single.people_per_ticket, "override forces 2 over a detected nil"
  end
end
