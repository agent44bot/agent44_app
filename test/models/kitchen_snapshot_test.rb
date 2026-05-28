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

  test "tickets_sold_by_week groups observed sales into Monday-start weeks" do
    add = ->(date, left) {
      KitchenSnapshot.create!(taken_on: date).kitchen_events.create!(
        url: "https://nykitchen.com/x", name: "X", start_at: 1.year.from_now, spots_left: left
      )
    }
    # Week of Mon May 4: -10 then -5 = 15 sold. (First snap has no prior → 0.)
    add.(Date.new(2026, 5, 4), 100)
    add.(Date.new(2026, 5, 5), 90)
    add.(Date.new(2026, 5, 6), 85)
    # Week of Mon May 11: -5 then -2 = 7 sold (first drop is vs May 6).
    add.(Date.new(2026, 5, 11), 80)
    add.(Date.new(2026, 5, 12), 78)

    weeks = KitchenSnapshot.tickets_sold_by_week

    assert_equal [ Date.new(2026, 5, 4), Date.new(2026, 5, 11) ], weeks.map { |w| w[:week_start] }
    assert_equal [ "May 4", "May 11" ], weeks.map { |w| w[:label] }
    assert_equal [ 15, 7 ], weeks.map { |w| w[:tickets] }
  end

  test "tickets_sold_by_week caps to the most recent limit_weeks, oldest first" do
    6.times do |w|
      base = Date.new(2026, 3, 1) + (w * 7) # six distinct Sundays
      KitchenSnapshot.create!(taken_on: base).kitchen_events.create!(
        url: "https://nykitchen.com/x", name: "X", start_at: 1.year.from_now, spots_left: 100
      )
      KitchenSnapshot.create!(taken_on: base + 1).kitchen_events.create!(
        url: "https://nykitchen.com/x", name: "X", start_at: 1.year.from_now, spots_left: 100 - (w + 1)
      )
    end

    weeks = KitchenSnapshot.tickets_sold_by_week(limit_weeks: 3)
    assert_equal 3, weeks.size
    assert weeks.first[:week_start] < weeks.last[:week_start], "expected oldest → newest"
  end

  test "tickets_sold_by_month groups observed sales into calendar months" do
    add = ->(date, left) {
      KitchenSnapshot.create!(taken_on: date).kitchen_events.create!(
        url: "https://nykitchen.com/x", name: "X", start_at: 1.year.from_now, spots_left: left
      )
    }
    # April: -10 then -5 = 15 sold (first snap has no prior → 0).
    add.(Date.new(2026, 4, 20), 100)
    add.(Date.new(2026, 4, 25), 90)
    add.(Date.new(2026, 4, 28), 85)
    # May: -5 then -2 = 7 sold (first May drop is vs Apr 28).
    add.(Date.new(2026, 5, 2), 80)
    add.(Date.new(2026, 5, 9), 78)

    months = KitchenSnapshot.tickets_sold_by_month

    assert_equal [ Date.new(2026, 4, 1), Date.new(2026, 5, 1) ], months.map { |m| m[:month_start] }
    assert_equal [ "Apr 2026", "May 2026" ], months.map { |m| m[:label] }
    assert_equal [ 15, 7 ], months.map { |m| m[:tickets] }
  end

  test "classes_ended_between returns each class's final observation in the window" do
    url = "https://nykitchen.com/events/x"
    KitchenSnapshot.create!(taken_on: Date.new(2026, 4, 10)).kitchen_events.create!(
      url: url, name: "X", start_at: Date.new(2026, 4, 15).noon, spots_left: 8, capacity: 10)
    KitchenSnapshot.create!(taken_on: Date.new(2026, 4, 12)).kitchen_events.create!(
      url: url, name: "X", start_at: Date.new(2026, 4, 15).noon, spots_left: 3, capacity: 10) # final

    events = KitchenSnapshot.classes_ended_between(Date.new(2026, 4, 1), Date.new(2026, 4, 30))
    assert_equal 1, events.size
    assert_equal 3, events.first.spots_left # last observation wins

    assert KitchenSnapshot.any_classes_between?(Date.new(2026, 4, 1), Date.new(2026, 4, 30))
    refute KitchenSnapshot.any_classes_between?(Date.new(2026, 1, 1), Date.new(2026, 1, 31))
  end

  test "bookings_between/total + newly_sold_out_since track week-over-week activity" do
    wk_ago = Date.current - 7
    older = KitchenSnapshot.create!(taken_on: wk_ago)
    older.kitchen_events.create!(url: "u/a", name: "A", start_at: 10.days.from_now, spots_left: 10, capacity: 10, price: "100.00", availability: "InStock")
    older.kitchen_events.create!(url: "u/b", name: "B", start_at: 10.days.from_now, spots_left: 5,  capacity: 5,  price: "50.00",  availability: "InStock")
    now = KitchenSnapshot.create!(taken_on: Date.current)
    now.kitchen_events.create!(url: "u/a", name: "A", start_at: 10.days.from_now, spots_left: 3, capacity: 10, price: "100.00", availability: "InStock") # sold 7
    now.kitchen_events.create!(url: "u/b", name: "B", start_at: 10.days.from_now, spots_left: 0, capacity: 5,  price: "50.00",  availability: "SoldOut")  # sold 5, flipped sold out

    rows = KitchenSnapshot.bookings_between(wk_ago, Date.current)
    assert_equal "u/a", rows.first[:event].url # biggest mover
    assert_equal 7,     rows.first[:tickets]
    assert_equal 700.0, rows.first[:revenue]

    total = KitchenSnapshot.bookings_total(wk_ago, Date.current)
    assert_equal 12,    total[:tickets]
    assert_equal 950.0, total[:revenue]

    assert_equal [ "u/b" ], KitchenSnapshot.newly_sold_out_since(wk_ago).map(&:url) # B flipped, A did not
  end

  test "calendar_churn diffs the class list vs ~a week ago" do
    wk_ago = Date.current - 7
    older = KitchenSnapshot.create!(taken_on: wk_ago)
    older.kitchen_events.create!(url: "u/keep",     name: "Keep",     start_at: 10.days.from_now, price: "50.00")
    older.kitchen_events.create!(url: "u/gone",     name: "Gone",     start_at: 10.days.from_now, price: "50.00")
    older.kitchen_events.create!(url: "u/repriced", name: "Repriced", start_at: 10.days.from_now, price: "50.00")
    now = KitchenSnapshot.create!(taken_on: Date.current)
    now.kitchen_events.create!(url: "u/keep",     name: "Keep",     start_at: 10.days.from_now, price: "50.00")
    now.kitchen_events.create!(url: "u/repriced", name: "Repriced", start_at: 10.days.from_now, price: "60.00") # price change
    now.kitchen_events.create!(url: "u/new",      name: "New",      start_at: 10.days.from_now, price: "70.00") # added

    churn = KitchenSnapshot.calendar_churn(wk_ago)
    assert_equal 1, churn[:added]         # u/new
    assert_equal 1, churn[:removed]       # u/gone
    assert_equal 1, churn[:price_changes] # u/repriced 50 → 60
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

  test "newly_sold_out_since counts genuine sellouts, not sales cutoffs" do
    today = Date.current
    prev = KitchenSnapshot.create!(taken_on: today - 7)
    prev.kitchen_events.create!(url: "u/sellout", name: "Sellout", start_at: 3.days.from_now, availability: "InStock", spots_left: 5)
    prev.kitchen_events.create!(url: "u/cutoff",  name: "Cutoff",  start_at: 3.days.from_now, availability: "InStock", spots_left: 20)

    now = KitchenSnapshot.create!(taken_on: today)
    now.kitchen_events.create!(url: "u/sellout", name: "Sellout", start_at: 3.days.from_now, availability: "SoldOut", spots_left: 0)
    now.kitchen_events.create!(url: "u/cutoff",  name: "Cutoff",  start_at: 3.days.from_now, availability: "Closed",  spots_left: 20)

    urls = KitchenSnapshot.newly_sold_out_since(today - 1).map(&:url)
    assert_includes     urls, "u/sellout"
    assert_not_includes urls, "u/cutoff" # "Tickets no longer available" != sold out
  end

  test "bookings_between ignores a sales cutoff (no phantom booking)" do
    today = Date.current
    from = KitchenSnapshot.create!(taken_on: today - 7)
    from.kitchen_events.create!(url: "u/cutoff", name: "Cutoff", start_at: 3.days.from_now, availability: "InStock", spots_left: 25, price: "57.00")
    to = KitchenSnapshot.create!(taken_on: today)
    to.kitchen_events.create!(url: "u/cutoff", name: "Cutoff", start_at: 3.days.from_now, availability: "Closed", spots_left: 0, price: "57.00")

    cutoff_rows = KitchenSnapshot.bookings_between(today - 7, today).select { |r| r[:event].url == "u/cutoff" }
    assert_empty cutoff_rows # 25 -> 0 is a closure, not 25 tickets sold
  end

  test "period_rollups hides retrospective periods until history covers them, then reveals" do
    today    = Date.current
    lw_start = today.beginning_of_week(:monday) - 7 # last week's Monday

    recent = KitchenSnapshot.create!(taken_on: today)
    recent.kitchen_events.create!(url: "u/lw", name: "Last-week class",
      start_at: (lw_start + 2).to_time, price: "50.00", capacity: 10, spots_left: 4, availability: "InStock")

    # Coverage starts today (after last week) → "Last week" hidden.
    refute_includes KitchenSnapshot.period_rollups(recent).map { |p| p[:label] }, "Last week"

    # Extend history to before last week → it returns on its own.
    KitchenSnapshot.create!(taken_on: lw_start - 1)
    assert_includes KitchenSnapshot.period_rollups(KitchenSnapshot.latest).map { |p| p[:label] }, "Last week"
  end

  test "period_rollups total_count counts every class; count is priced only" do
    today    = Date.current
    nw_start = today.end_of_week(:monday) + 1 # next Monday — always in the future

    snap = KitchenSnapshot.create!(taken_on: today)
    snap.kitchen_events.create!(url: "u/priced", name: "Priced class",
      start_at: (nw_start + 1).to_time, price: "50.00", capacity: 10, spots_left: 4, availability: "InStock")
    snap.kitchen_events.create!(url: "u/unpriced", name: "Unpriced class",
      start_at: (nw_start + 1).to_time, availability: "other") # no capacity/price

    nw = KitchenSnapshot.period_rollups(snap).find { |p| p[:label] == "Next week" }
    assert_equal 2, nw[:total_count], "total_count counts every class in the period"
    assert_equal 1, nw[:count], "count counts only priced/capacity-known classes"
  end

  test "tickets_sold_today ignores closed-class spot drops (cutoff, not a sale)" do
    today = Date.current
    y = KitchenSnapshot.create!(taken_on: today - 1)
    y.kitchen_events.create!(url: "u/a", name: "A", start_at: (today + 3).to_time, spots_left: 10, capacity: 20, availability: "InStock")
    y.kitchen_events.create!(url: "u/b", name: "B", start_at: (today + 3).to_time, spots_left: 8,  capacity: 20, availability: "InStock")
    s = KitchenSnapshot.create!(taken_on: today)
    s.kitchen_events.create!(url: "u/a", name: "A", start_at: (today + 3).to_time, spots_left: 7, capacity: 20, availability: "InStock") # sold 3
    s.kitchen_events.create!(url: "u/b", name: "B", start_at: (today + 3).to_time, spots_left: 0, capacity: 20, availability: "Closed")  # cutoff, not 8 sold

    assert_equal 3, s.tickets_sold_today
  end

  test "bookings_daily_total sums daily real sales, skips closed, counts dropped-off classes" do
    d = ->(n) { Date.current - n }
    # d4: baseline; A and C selling, B selling.
    s4 = KitchenSnapshot.create!(taken_on: d.call(4))
    s4.kitchen_events.create!(url: "u/a", name: "A", start_at: d.call(2).to_time, price: "50.00", capacity: 20, spots_left: 10, availability: "InStock")
    s4.kitchen_events.create!(url: "u/b", name: "B", start_at: d.call(2).to_time, price: "40.00", capacity: 20, spots_left: 4,  availability: "InStock")
    s4.kitchen_events.create!(url: "u/c", name: "C", start_at: d.call(0).to_time, price: "30.00", capacity: 10, spots_left: 5,  availability: "InStock")
    # d3: A sells 3.
    s3 = KitchenSnapshot.create!(taken_on: d.call(3))
    s3.kitchen_events.create!(url: "u/a", name: "A", start_at: d.call(2).to_time, price: "50.00", capacity: 20, spots_left: 7, availability: "InStock")
    s3.kitchen_events.create!(url: "u/b", name: "B", start_at: d.call(2).to_time, price: "40.00", capacity: 20, spots_left: 4, availability: "InStock")
    s3.kitchen_events.create!(url: "u/c", name: "C", start_at: d.call(0).to_time, price: "30.00", capacity: 10, spots_left: 5, availability: "InStock")
    # d2: C sells 3; B goes Closed (4-left cutoff — must NOT count); A ran and drops off.
    s2 = KitchenSnapshot.create!(taken_on: d.call(2))
    s2.kitchen_events.create!(url: "u/b", name: "B", start_at: d.call(2).to_time, price: "40.00", capacity: 20, spots_left: 0, availability: "Closed")
    s2.kitchen_events.create!(url: "u/c", name: "C", start_at: d.call(0).to_time, price: "30.00", capacity: 10, spots_left: 2, availability: "InStock")
    # d1: C sells 1.
    s1 = KitchenSnapshot.create!(taken_on: d.call(1))
    s1.kitchen_events.create!(url: "u/c", name: "C", start_at: d.call(0).to_time, price: "30.00", capacity: 10, spots_left: 1, availability: "InStock")

    # Range d3..d1: A +3 ($150, while listed), C +3 ($90) + C +1 ($30); B closed → skipped.
    res = KitchenSnapshot.bookings_daily_total(d.call(3), d.call(1))
    assert_equal 7, res[:tickets]
    assert_in_delta 270.0, res[:revenue], 0.01
  end
end
