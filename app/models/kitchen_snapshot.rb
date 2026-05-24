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
      prev_e = prev_events[e.url]
      next 0 unless prev_e
      [prev_e.spots_left - e.spots_left, 0].max
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
  # Snapshots are daily, so pace resolves to ~day granularity: good for
  # "filled in 3 days vs 12", not sub-day claims. `days_to_sellout` is only
  # set when we saw the class go from open → sold out (not when we first
  # caught it already sold out), so the "Sold out in N days" badge is honest.
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
      .sort_by { |h| [-h[:pace], h[:days_to_sellout] || 9_999, -h[:observed_sold]] }
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
      days_until    = [(e.start_at.to_date - today).to_i, 1].max
      needed_pace   = (e.spots_left.to_f / days_until).round(1)
      observed_pace = pace.dig(e.url, :pace) || 0.0
      shortfall     = (needed_pace - observed_pace).round(1)
      next unless shortfall.positive? # only classes behind the rate they need

      { event: e, needed_pace: needed_pace, observed_pace: observed_pace,
        shortfall: shortfall, days_until: days_until }
    }.sort_by { |h| [-h[:shortfall], h[:days_until]] }
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
      observed_sold = (first_spots && last_spots) ? [first_spots - last_spots, 0].max : 0

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
    start_of_week = Date.current.beginning_of_week(:sunday)
    snaps = where(taken_on: start_of_week..Date.current)
      .order(taken_on: :asc)
      .to_a

    (0..6).each_with_object({}) do |wday, h|
      snap = snaps.find { |s| s.taken_on.wday == wday }
      h[wday] = snap ? snap.tickets_sold_today : nil
    end
  end
end
