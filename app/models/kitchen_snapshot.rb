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
