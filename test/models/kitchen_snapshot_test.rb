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

  # Seed one class across `days` daily snapshots, dropping spots_left from
  # `from` to `to` linearly, flipping availability to soldout once it hits 0.
  def seed_class(url, from:, to:, days:, name: url)
    today = Date.current
    (0...days).each do |i|
      taken = today - (days - 1 - i)
      spots = (from - (from - to) * i / (days - 1).to_f).round
      snap  = KitchenSnapshot.find_or_create_by!(taken_on: taken)
      snap.kitchen_events.create!(
        url: url, name: name, start_at: 1.month.from_now,
        spots_left: spots, capacity: from,
        availability: spots <= 0 ? "SoldOut" : "InStock"
      )
    end
  end

  test "selling_fastest ranks by observed pace and tags witnessed sellouts" do
    # Fast: 20 → 0 over 5 days = 4/day, sold out on the final (today) snapshot.
    seed_class("https://nykitchen.com/fast", from: 20, to: 0, days: 5, name: "Fast")
    # Slow: 20 → 14 over 5 days = ~1.2/day, never sold out.
    seed_class("https://nykitchen.com/slow", from: 20, to: 14, days: 5, name: "Slow")

    ranked = KitchenSnapshot.selling_fastest
    assert_equal %w[Fast Slow], ranked.map { |r| r[:event].name }
    assert_equal 5.0, ranked.first[:pace] # 20 tickets / 4 days to sellout
    assert_equal 4, ranked.first[:days_to_sellout] # open day 0 → sold out day 4
    assert_nil ranked.last[:days_to_sellout]
  end

  test "selling_fastest does not tag a class we only ever saw sold out" do
    seed_class("https://nykitchen.com/late", from: 0, to: 0, days: 4, name: "Late")

    ranked = KitchenSnapshot.selling_fastest
    # Never witnessed open and zero observed sales → excluded entirely.
    assert_empty ranked
  end

  # For the all-time toggle: a class whose date has passed isn't in the
  # latest snapshot's `upcoming`, so :upcoming skips it, but :all surfaces it.
  def seed_past_class(url, from:, to:, days:, start_at:, name: url)
    today = Date.current
    (0...days).each do |i|
      taken = today - (days - 1 - i)
      spots = (from - (from - to) * i / (days - 1).to_f).round
      snap  = KitchenSnapshot.find_or_create_by!(taken_on: taken)
      snap.kitchen_events.create!(
        url: url, name: name, start_at: start_at,
        spots_left: spots, capacity: from,
        availability: spots <= 0 ? "SoldOut" : "InStock"
      )
    end
  end

  test "selling_fastest :all includes past classes that :upcoming omits" do
    # Past class that sold out fast; its date is already behind us.
    seed_past_class("https://nykitchen.com/past", from: 12, to: 0, days: 4,
                    start_at: 1.day.ago, name: "Past Sellout")
    # A current upcoming class so there's a latest snapshot with upcoming events.
    seed_class("https://nykitchen.com/future", from: 12, to: 9, days: 4, name: "Future")

    upcoming = KitchenSnapshot.selling_fastest(scope: :upcoming).map { |r| r[:event].name }
    all_time = KitchenSnapshot.selling_fastest(scope: :all, window_weeks: nil).map { |r| r[:event].name }

    assert_equal %w[Future], upcoming
    assert_includes all_time, "Past Sellout"
    assert_equal "Past Sellout", all_time.first # sold out fastest → ranks top
  end

  test "needs_a_push ranks classes by their shortfall vs needed pace" do
    today = Date.current
    # Behind: 20 seats open, class in 5 days → needs 4/day, selling ~0.
    KitchenSnapshot.create!(taken_on: today).tap do |s|
      s.kitchen_events.create!(url: "u/behind", name: "Behind", start_at: today + 5,
        spots_left: 20, capacity: 24, availability: "InStock")
      # On pace: only 2 seats open → below MIN_OPEN_SEATS, excluded.
      s.kitchen_events.create!(url: "u/almostfull", name: "AlmostFull", start_at: today + 5,
        spots_left: 2, capacity: 24, availability: "InStock")
      # Far out: 20 open but the class is 90 days away → outside the window.
      s.kitchen_events.create!(url: "u/faraway", name: "FarAway", start_at: today + 90,
        spots_left: 20, capacity: 24, availability: "InStock")
      # Sold out → never needs a push.
      s.kitchen_events.create!(url: "u/done", name: "Done", start_at: today + 5,
        spots_left: 0, capacity: 24, availability: "SoldOut")
    end

    ranked = KitchenSnapshot.needs_a_push
    assert_equal %w[Behind], ranked.map { |r| r[:event].name }
    assert_equal 4.0, ranked.first[:needed_pace]
    assert_operator ranked.first[:shortfall], :>, 0
  end

  test "needs_a_push drops a class already selling fast enough to fill" do
    today = Date.current
    # 4 seats open, class in 8 days → needs 0.5/day. It's been selling ~3/day,
    # so it'll fill easily → not at risk, excluded.
    [7, 4].each_with_index do |spots, i|
      taken = today - (1 - i) # yesterday, then today
      snap  = KitchenSnapshot.find_or_create_by!(taken_on: taken)
      snap.kitchen_events.create!(url: "u/fine", name: "Fine", start_at: today + 8,
        spots_left: spots, capacity: 24, availability: "InStock")
    end

    assert_empty KitchenSnapshot.needs_a_push
  end

  test "ended_emptiest ranks past classes by unsold seats, skipping sellouts" do
    today = Date.current
    snap = KitchenSnapshot.create!(taken_on: today - 1) # a recent snapshot is "latest"
    snap.kitchen_events.create!(url: "u/flop", name: "Flop", start_at: today - 3,
      spots_left: 18, capacity: 24, availability: "InStock")
    snap.kitchen_events.create!(url: "u/soft", name: "Soft", start_at: today - 3,
      spots_left: 5, capacity: 24, availability: "InStock")
    # Sold out → not an underperformer, excluded.
    snap.kitchen_events.create!(url: "u/hit", name: "Hit", start_at: today - 3,
      spots_left: 0, capacity: 24, availability: "SoldOut")
    # Only 1 seat open → below MIN_OPEN_SEATS, excluded.
    snap.kitchen_events.create!(url: "u/nearly", name: "Nearly", start_at: today - 3,
      spots_left: 1, capacity: 24, availability: "InStock")
    # Future class → not "ended" yet, excluded.
    snap.kitchen_events.create!(url: "u/future", name: "Future", start_at: today + 10,
      spots_left: 20, capacity: 24, availability: "InStock")

    ranked = KitchenSnapshot.ended_emptiest
    assert_equal %w[Flop Soft], ranked.map { |r| r[:event].name }
    assert_equal 18, ranked.first[:unsold]
  end
end
