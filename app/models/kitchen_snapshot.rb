class KitchenSnapshot < ApplicationRecord
  has_many :kitchen_events, dependent: :destroy
  has_many :kitchen_ticket_digests, dependent: :destroy

  validates :taken_on, presence: true, uniqueness: true

  def self.latest
    order(taken_on: :desc).first
  end

  def self.latest_before(date)
    where("taken_on < ?", date).order(taken_on: :desc).first
  end

  # Tickets sold since the previous day's snapshot. Diffs this
  # snapshot's spots_left against the immediately-previous snapshot's
  # spots_left, per event URL. (Don't use last_known_spots_left — it's
  # a rolling high-water mark in scrape_kitchen_job, not yesterday's
  # value, so summing against it returns cumulative sales since we
  # started watching, not today's.)
  #
  # Per-event delta is floored at 0 so refunds/availability resets
  # can't push the total negative. Events that exist only in one
  # snapshot are ignored.
  def tickets_sold_today
    prev = KitchenSnapshot.latest_before(taken_on)
    return 0 unless prev

    prev_events = prev.kitchen_events.where.not(spots_left: nil).index_by(&:url)
    kitchen_events.where.not(spots_left: nil).sum do |e|
      # "Tickets no longer available" (Closed) drops spots to 0 as a sales
      # cutoff, not a sale — don't count that as tickets sold.
      next 0 if e.sales_ended?
      prev_e = prev_events[e.url]
      next 0 unless prev_e
      [ prev_e.spots_left - e.spots_left, 0 ].max
    end
  end

  # Average daily ticket sales over the last `days` snapshots before today.
  # Excludes today so the average doesn't drag the pace toward itself.
  # Returns nil if we don't have enough history to compute a meaningful avg.
  def self.tickets_sold_daily_avg(days: 14)
    snaps = where(taken_on: (days.days.ago.to_date)...Date.current)
      .order(taken_on: :asc)
      .to_a
    return nil if snaps.size < 3

    totals = snaps.map(&:tickets_sold_today)
    (totals.sum.to_f / totals.size).round(1)
  end

  # Average tickets sold grouped by day-of-week (0=Sunday … 6=Saturday)
  # over the last `weeks` of snapshots, excluding today.
  # Returns a hash keyed by wday with float values. Missing days are 0.0.
  def self.tickets_sold_by_wday(weeks: 6)
    snaps = where(taken_on: (weeks.weeks.ago.to_date)...Date.current)
      .order(taken_on: :asc)
      .to_a

    buckets = Hash.new { |h, k| h[k] = [] }
    snaps.each { |s| buckets[s.taken_on.wday] << s.tickets_sold_today }

    (0..6).each_with_object({}) do |wday, h|
      vals = buckets[wday]
      h[wday] = vals.any? ? (vals.sum.to_f / vals.size).round(1) : 0.0
    end
  end

  # Tickets sold per calendar week (Sunday-start) since tracking began,
  # oldest → newest, capped to the last `limit_weeks`. Sums tickets_sold_today
  # (day-over-day spots_left drops) within each week — the same observed-sales
  # basis as the day-of-week chart, so the first tracked week reads low (we
  # only count drops we witnessed). Returns an array of
  # { week_start: Date, label: "May 17", tickets: Integer }.
  def self.tickets_sold_by_week(limit_weeks: 12)
    order(taken_on: :asc).to_a
      .group_by { |s| s.taken_on.beginning_of_week(:monday) }
      .map { |week_start, snaps|
        { week_start: week_start,
          label:      week_start.strftime("%b %-d"),
          tickets:    snaps.sum { |s| s.tickets_sold_today.to_i } }
      }
      .sort_by { |row| row[:week_start] }
      .last(limit_weeks)
  end

  # Tickets sold per calendar month since tracking began, oldest → newest,
  # capped to the last `limit_months`. Same observed-sales basis as
  # tickets_sold_by_week — the first tracked month is partial (we only count
  # drops from the day tracking started). Returns an array of
  # { month_start: Date, label: "Apr 2026", tickets: Integer }.
  def self.tickets_sold_by_month(limit_months: 12)
    order(taken_on: :asc).to_a
      .group_by { |s| s.taken_on.beginning_of_month }
      .map { |month_start, snaps|
        { month_start: month_start,
          label:       month_start.strftime("%b %Y"),
          tickets:     snaps.sum { |s| s.tickets_sold_today.to_i } }
      }
      .sort_by { |row| row[:month_start] }
      .last(limit_months)
  end

  # Ranks classes by how fast they're selling, for the "Selling fastest"
  # card on the List Agent page. Returns up to `limit` hashes the view
  # renders directly.
  #
  # scope: :upcoming — only classes still on the latest snapshot's calendar
  #        :all       — every class we've ever tracked (past + future)
  #
  # Pace is observed sell-through: the drop in spots_left between the first
  # and last snapshot we've seen the class in, divided by the days over
  # which that drop happened (days-to-sellout for classes we watched sell
  # out, days observed otherwise). Using the spots_left delta keeps it
  # capacity-independent and counts only sales we actually witnessed — so a
  # class listed long before we started watching can't fake a fast pace.
  #
  # Snapshots are daily, so pace resolves to ~day granularity, not sub-day
  # claims. `days_to_sellout` (set only when we watched a class go open →
  # sold out) is used as the pace denominator and a sort tiebreak — it's not
  # shown, since it's measured from when we started tracking, not listing.
  #
  # window_weeks bounds the snapshot lookback (nil = all history). The
  # representative event for each class is its most recent observation.
  def self.selling_fastest(limit: 5, scope: :upcoming, window_weeks: 8, snapshot: latest)
    return [] unless snapshot

    urls = nil
    if scope == :upcoming
      urls = snapshot.kitchen_events.upcoming.distinct.pluck(:url)
      return [] if urls.empty?
    end

    ranked = observed_pace_by_url(urls: urls, window_weeks: window_weeks)
      .values
      .select { |h| h[:pace].positive? || h[:days_to_sellout] }
      .sort_by { |h| [ -h[:pace], h[:days_to_sellout] || 9_999, -h[:observed_sold] ] }
      .first(limit)

    hydrate_events(ranked)
  end

  # Upcoming classes at risk of not filling — the "Needs a push" card. Ranks
  # by shortfall: how many tickets/day a class must still sell to fill by its
  # date (spots_left / days_until) minus the pace it's actually selling at.
  # A positive shortfall means it's behind the rate it needs.
  #
  # Only flags classes with real empty seats (>= MIN_OPEN_SEATS), not sold
  # out, and within AT_RISK_WINDOW_DAYS — a class months out has plenty of
  # runway and isn't actionable yet. Pure "slowest by pace" would instead
  # surface brand-new and far-future listings that are selling fine; the
  # needed-vs-actual gap is what makes a class genuinely at risk.
  AT_RISK_WINDOW_DAYS = 45
  MIN_OPEN_SEATS = 3

  def self.needs_a_push(limit: 5, snapshot: latest)
    return [] unless snapshot

    today = Date.current
    candidates = snapshot.kitchen_events.upcoming.to_a.select { |e|
      !e.sold_out? && e.spots_left.to_i >= MIN_OPEN_SEATS &&
        (e.start_at.to_date - today).to_i.between?(0, AT_RISK_WINDOW_DAYS)
    }
    return [] if candidates.empty?

    pace = observed_pace_by_url(urls: candidates.map(&:url), window_weeks: 8)

    candidates.filter_map { |e|
      days_until    = [ (e.start_at.to_date - today).to_i, 1 ].max
      needed_pace   = (e.spots_left.to_f / days_until).round(1)
      observed_pace = pace.dig(e.url, :pace) || 0.0
      shortfall     = (needed_pace - observed_pace).round(1)
      next unless shortfall.positive? # only classes behind the rate they need

      { event: e, needed_pace: needed_pace, observed_pace: observed_pace,
        shortfall: shortfall, days_until: days_until }
    }.sort_by { |h| [ -h[:shortfall], h[:days_until] ] }
     .first(limit)
  end

  # Retrospective companion to needs_a_push: past classes that ran with the
  # most unsold seats — the "Ended emptiest" all-time view. Ranks by seats
  # still open at the last snapshot we saw each class in (≈ its show date,
  # since classes drop off the calendar after they happen). Excludes classes
  # that sold out and ones with no inventory signal.
  def self.ended_emptiest(limit: 5, snapshot: latest)
    return [] unless snapshot

    rows = KitchenEvent
      .joins(:kitchen_snapshot)
      .where("kitchen_events.start_at < ?", Time.current)
      .order("kitchen_snapshots.taken_on ASC")
      .pluck("kitchen_events.url", "kitchen_snapshots.taken_on",
             "kitchen_events.spots_left", "kitchen_events.availability",
             "kitchen_events.id")
    sold_out_rx = /soldout|closed/

    ranked = rows.group_by(&:first).filter_map { |_url, obs|
      last  = obs.last
      spots = last[2]
      next if spots.nil? || spots < MIN_OPEN_SEATS         # sold out, full, or no signal
      next if last[3].to_s.downcase =~ sold_out_rx         # ended sold out / closed
      { event_id: last[4], unsold: spots }
    }.sort_by { |h| -h[:unsold] }
     .first(limit)

    hydrate_events(ranked)
  end

  # Past classes whose start_at fell within [from, to] (Dates), each returned as
  # the LAST KitchenEvent we observed for it — i.e. its final state (≈ its show
  # date, since classes drop off the calendar after they run). Powers the
  # Analyst page's retrospective ranges (booked vs missed revenue for a past
  # period). The window is capped at "now" so a partially-elapsed period only
  # counts classes that have actually happened.
  def self.classes_ended_between(from, to)
    upper = [ to.end_of_day, Time.current ].min
    return [] if from.beginning_of_day > upper

    last_ids = KitchenEvent.joins(:kitchen_snapshot)
      .where(start_at: from.beginning_of_day..upper)
      .order("kitchen_snapshots.taken_on ASC")
      .pluck("kitchen_events.url", "kitchen_events.id")
      .group_by(&:first).map { |_url, obs| obs.last.last }
    KitchenEvent.where(id: last_ids).to_a
  end

  # Cheap existence check for whether any (past) class falls in a window — used
  # to decide whether to even offer a retrospective range button.
  def self.any_classes_between?(from, to)
    upper = [ to.end_of_day, Time.current ].min
    return false if from.beginning_of_day > upper
    KitchenEvent.where(start_at: from.beginning_of_day..upper).exists?
  end

  # Face-value revenue rollup for a set of events: { count, sold, total, left,
  # pct }. Same basis as the Analyst dashboard — only capacity-known classes
  # count; `pct` is seats sold / seats total. Shared so the dashboard and the
  # recap email can't disagree.
  def self.revenue_rollup(events)
    priced = events.select(&:capacity_known?)
    sold   = priced.sum(&:revenue_sold)
    total  = priced.sum(&:revenue_total)
    {
      count: priced.size,
      sold:  sold,
      total: total,
      left:  total - sold,
      # Revenue-based so the % reconciles with the dollar figures it sits next
      # to ($sold / $total), rather than seats-sold / seats-total.
      pct:   total.positive? ? (100.0 * sold / total).round : nil
    }
  end

  # The recap email's "by period" scoreboard: a rollup for each standard window
  # that has data, oldest → newest. Past windows (kind: :past) read as
  # booked/missed; forward windows (kind: :forward) as sold/left-to-sell.
  # Windows match the Analyst range control exactly.
  def self.period_rollups(snapshot)
    return [] unless snapshot
    today      = Date.current
    week_start = today.beginning_of_week(:monday) # Mon→Sun weeks (Lora's preference)
    week_end   = today.end_of_week(:monday)       # the Sunday
    upcoming   = snapshot.kitchen_events.upcoming.to_a # forward source (incl. sold-out — booked revenue counts)
    fwd = ->(from, to) {
      upcoming.select { |e| d = e.start_at&.to_date; d && d >= from && (to.nil? || d <= to) }
    }

    # Retrospective periods reconstruct sold/% from snapshot deltas, so they're
    # only trustworthy once our history reaches back to before the window began
    # (otherwise early sales we never saw make them read biased-low). Hide a
    # :past period until coverage catches up — then it returns on its own.
    earliest = minimum(:taken_on)
    next_mo  = today.next_month       # full calendar month after the current one
    two_mo   = next_mo.next_month     # the month after that (2 months from now)
    three_mo = two_mo.next_month      # 3 months from now
    # Month rows are labelled by name ("June"); append the year only when it
    # crosses into a different year so Dec→Jan stays unambiguous.
    mlabel   = ->(d) { d.year == today.year ? d.strftime("%B") : d.strftime("%B %Y") }

    [
      { key: "lastmonth", label: "Last month", kind: :past, from: today.last_month.beginning_of_month,
        events: classes_ended_between(today.last_month.beginning_of_month, today.last_month.end_of_month) },
      { key: "lastweek",  label: "Last week",  kind: :past, from: week_start - 7,
        events: classes_ended_between(week_start - 7, week_start - 1) },
      { key: "thisweek",  label: "Current week",  kind: :forward, events: fwd.call(today, week_end) },
      { key: "nextweek",  label: "Next week",     kind: :forward, events: fwd.call(week_end + 1, week_end + 7) },
      { key: "thismonth", label: "Rest of #{mlabel.call(today)}", kind: :forward, events: fwd.call(today, today.end_of_month) },
      { key: "nextmonth", label: mlabel.call(next_mo),  kind: :forward, events: fwd.call(next_mo.beginning_of_month, next_mo.end_of_month) },
      { key: "twomonths", label: mlabel.call(two_mo),   kind: :forward, events: fwd.call(two_mo.beginning_of_month, two_mo.end_of_month) },
      { key: "threemonths", label: mlabel.call(three_mo), kind: :forward, events: fwd.call(three_mo.beginning_of_month, three_mo.end_of_month) }
    ].filter_map { |d|
      next if d[:kind] == :past && (earliest.nil? || earliest > d[:from])
      r = revenue_rollup(d[:events])
      next if r[:count].zero?
      # count = priced classes (what the dollars are built from); total_count =
      # every class in the period (incl. ones with no capacity data), matching
      # the dashboard's per-week "(N)" headcount.
      d.except(:events, :from).merge(r).merge(total_count: d[:events].size)
    }
  end

  # Booking activity — tickets sold (spots_left decrease) per class between the
  # last snapshot on/before `from` and the one on/before `to` (Dates). Returns
  # [{ event:, tickets:, revenue: }] for classes that sold (>0), tickets desc.
  # This is "what sold this week" (booking events), independent of class date.
  def self.bookings_between(from, to)
    from_snap = where("taken_on <= ?", from).order(taken_on: :desc).first
    to_snap   = where("taken_on <= ?", to).order(taken_on: :desc).first
    return [] unless from_snap && to_snap && from_snap.id != to_snap.id

    start_spots = from_snap.kitchen_events.where.not(spots_left: nil).pluck(:url, :spots_left).to_h
    to_snap.kitchen_events.where.not(spots_left: nil).filter_map { |e|
      next if e.sales_ended? # a "Tickets no longer available" cutoff isn't a booking
      s0   = start_spots[e.url]
      sold = s0 ? s0 - e.spots_left : 0
      next if sold <= 0
      { event: e, tickets: sold, revenue: sold * e.price_value }
    }.sort_by { |h| -h[:tickets] }
  end

  # { tickets:, revenue: } totals for bookings_between.
  def self.bookings_total(from, to)
    rows = bookings_between(from, to)
    { tickets: rows.sum { |r| r[:tickets] }, revenue: rows.sum { |r| r[:revenue] } }
  end

  # { tickets:, revenue: } of real tickets sold across a date range, summed
  # day-over-day — the same observed-sales basis as tickets_sold_by_week (so the
  # report's "Booked this week" reconciles with the weekly chart). Unlike
  # bookings_total (which compares two endpoints over the still-listed cohort),
  # this also captures classes that sold and then ran off the calendar mid-range,
  # and skips "Tickets no longer available" cutoffs.
  def self.bookings_daily_total(from, to)
    tickets = 0
    revenue = 0.0
    where(taken_on: from..to).order(taken_on: :asc).each do |s|
      prev = latest_before(s.taken_on)
      next unless prev
      prev_events = prev.kitchen_events.where.not(spots_left: nil).index_by(&:url)
      s.kitchen_events.where.not(spots_left: nil).each do |e|
        next if e.sales_ended?
        prev_e = prev_events[e.url]
        next unless prev_e
        drop = prev_e.spots_left - e.spots_left
        next if drop <= 0
        tickets += drop
        revenue += drop * e.price_value
      end
    end
    { tickets: tickets, revenue: revenue }
  end

  # Sam's weekly calendar churn: how the class list changed vs the last snapshot
  # on/before `since` — { added:, removed:, price_changes: } counts. Reuses the
  # daily-digest diff builder, just over a 7-day span instead of day-over-day.
  def self.calendar_churn(since)
    latest = self.latest
    prev   = where("taken_on <= ?", since).order(taken_on: :desc).first
    return { added: 0, removed: 0, price_changes: 0 } unless latest && prev && latest.id != prev.id

    current = latest.kitchen_events.map do |e|
      { url: e.url, name: e.name, start_at: e.start_at, end_at: e.end_at,
        price: e.price, availability: e.availability, venue: e.venue,
        instructor: e.instructor, description: e.description,
        spots_left: e.spots_left, capacity: e.capacity }
    end
    d = NyKitchenDigestBuilder.build(current: current, previous_snapshot: prev, today: Date.current)
    { added: d[:newly_added].size, removed: d[:removed].size, price_changes: d[:price_changes].size }
  end

  # Upcoming classes sold out now that were tracked-and-open at the last snapshot
  # on/before `date` — i.e. genuinely flipped to sold out since then.
  def self.newly_sold_out_since(date)
    now  = latest or return []
    prev = where("taken_on <= ?", date).order(taken_on: :desc).first or return []
    prev_status = prev.kitchen_events.pluck(:url, :availability).to_h
    now.kitchen_events.upcoming.select { |e|
      e.truly_sold_out? && prev_status.key?(e.url) && prev_status[e.url].to_s.downcase !~ /soldout/
    }.sort_by(&:start_at)
  end

  # Observed sell-through pace per class URL, keyed by url. Pace is the drop
  # in spots_left between the first and last snapshot we've seen the class in,
  # over the days that drop took (days-to-sellout if we watched it sell out,
  # else days observed). Capacity-independent — counts only witnessed sales,
  # so a class listed before we started watching can't fake a fast pace.
  # `urls: nil` covers every tracked class; window_weeks: nil = all history.
  def self.observed_pace_by_url(urls: nil, window_weeks: nil)
    rel = KitchenEvent.joins(:kitchen_snapshot)
    rel = rel.where(kitchen_snapshots: { taken_on: window_weeks.weeks.ago.to_date.. }) if window_weeks
    rel = rel.where(url: urls) if urls

    rows = rel.order("kitchen_snapshots.taken_on ASC")
              .pluck("kitchen_events.url", "kitchen_snapshots.taken_on",
                     "kitchen_events.spots_left", "kitchen_events.availability",
                     "kitchen_events.id")
    sold_out_rx = /soldout|closed/

    rows.group_by(&:first).transform_values { |obs|
      first_on, first_spots = obs.first[1], obs.first[2]
      last_on,  last_spots  = obs.last[1],  obs.last[2]
      observed_sold = (first_spots && last_spots) ? [ first_spots - last_spots, 0 ].max : 0

      witnessed_open  = obs.first[3].to_s.downcase !~ sold_out_rx
      sold_out_on     = witnessed_open && (r = obs.find { |o| o[3].to_s.downcase =~ sold_out_rx }) ? r[1] : nil
      days_to_sellout = sold_out_on ? (sold_out_on - first_on).to_i : nil

      rate_days = (days_to_sellout && days_to_sellout.positive?) ? days_to_sellout : (last_on - first_on).to_i
      pace      = rate_days.positive? ? (observed_sold.to_f / rate_days) : observed_sold.to_f

      { event_id: obs.last[4], pace: pace.round(1), observed_sold: observed_sold,
        days_to_sellout: days_to_sellout, first_seen_on: first_on }
    }
  end

  # Replace each ranked hash's :event_id with the loaded KitchenEvent as
  # :event, preserving order and dropping any whose record vanished.
  def self.hydrate_events(ranked)
    events = KitchenEvent.where(id: ranked.map { |h| h[:event_id] }).index_by(&:id)
    ranked.filter_map { |h| (e = events[h[:event_id]]) && h.merge(event: e) }
  end

  # This week's tickets sold per day-of-week. Returns a hash keyed by
  # wday with the actual count (or nil for days that haven't happened yet
  # this week or have no snapshot).
  def self.tickets_sold_this_week_by_wday
    start_of_week = Date.current.beginning_of_week(:monday)
    snaps = where(taken_on: start_of_week..Date.current)
      .order(taken_on: :asc)
      .to_a

    (0..6).each_with_object({}) do |wday, h|
      snap = snaps.find { |s| s.taken_on.wday == wday }
      h[wday] = snap ? snap.tickets_sold_today : nil
    end
  end
end
