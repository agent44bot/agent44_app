class KitchenEvent < ApplicationRecord
  belongs_to :kitchen_snapshot

  validates :url, presence: true

  scope :upcoming, -> { where("start_at >= ?", Time.current).order(:start_at) }
  scope :sold_out, -> { where("LOWER(availability) LIKE ? OR LOWER(availability) LIKE ?", "%soldout%", "%closed%") }

  def sold_out?
    av = availability.to_s.downcase
    av.include?("soldout") || av.include?("closed")
  end

  # Canonical status bucket for filter chips + CSS targeting.
  # "soldout" takes priority over "closed" — Laura's request: when both
  # appear on the event page, show "Sold Out" on the list.
  def availability_status
    d = availability.to_s.downcase
    case d
    when /soldout/  then "soldout"
    when /closed/   then "closed"
    when /limited/  then "limited"
    when /instock/  then "instock"
    else                 "other"
    end
  end

  # Capacity helpers powering the week-level "% tickets sold" rollup.
  # Sold-out events have capacity snapshotted onto last_known_*; available
  # events expose live capacity/spots_left. Returns nil when we have no
  # capacity data at all (free community events, scraper didn't see numbers,
  # etc.) so the rollup can exclude them cleanly.
  def tickets_total
    capacity.presence || last_known_capacity.presence
  end

  def tickets_sold
    total = tickets_total
    return nil unless total
    remaining = if capacity.present?
      spots_left || 0
    else
      last_known_spots_left || 0
    end
    [total - remaining, 0].max
  end

  def capacity_known?
    tickets_total.present?
  end
end
