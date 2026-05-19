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

  # Tickets sold since the previous day's snapshot was taken. Each
  # event's last_known_spots_left is carried over from the previous
  # snapshot at scrape time, so (last_known - current) is the count
  # sold between snapshots. Sums across all events with both values
  # present. Capped at >= 0 per event (refunds/availability resets
  # would otherwise push individual deltas negative).
  def tickets_sold_today
    kitchen_events
      .where.not(spots_left: nil)
      .where.not(last_known_spots_left: nil)
      .sum { |e| [e.last_known_spots_left - e.spots_left, 0].max }
  end
end
