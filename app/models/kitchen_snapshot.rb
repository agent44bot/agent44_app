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
end
