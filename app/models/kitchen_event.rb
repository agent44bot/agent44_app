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
  # Three sources of capacity, in priority order:
  #   1. capacity / spots_left          — live "X of Y left" on Tock
  #   2. last_known_capacity / last_known_spots_left — snapshotted at sellout
  #   3. last_known_spots_left          — proxy: high-water mark of spots
  #                                       we've ever observed for the event,
  #                                       used when Tock never showed a Y.
  # The proxy under-counts true capacity (anything sold before we started
  # watching is invisible) so the resulting fill % is biased low, which is
  # the conservative direction. Returns nil when even the proxy is missing
  # (free events, never-scraped, etc.) so the rollup excludes cleanly.
  def tickets_total
    capacity.presence || last_known_capacity.presence || last_known_spots_left.presence
  end

  def tickets_sold
    if capacity.present?
      [capacity - (spots_left || 0), 0].max
    elsif last_known_capacity.present?
      [last_known_capacity - (last_known_spots_left || 0), 0].max
    elsif last_known_spots_left.present?
      # Proxy: tickets observed selling = high-water minus current
      [last_known_spots_left - (spots_left || 0), 0].max
    end
  end

  def capacity_known?
    tickets_total.present?
  end

  # True iff capacity_known? is satisfied only via the proxy fallback
  # (no real capacity from Tock, just our scraper's high-water mark).
  def capacity_via_proxy?
    capacity.blank? && last_known_capacity.blank? && last_known_spots_left.present?
  end
end
