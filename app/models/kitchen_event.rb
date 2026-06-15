class KitchenEvent < ApplicationRecord
  belongs_to :kitchen_snapshot

  validates :url, presence: true

  scope :upcoming, -> { where("start_at >= ?", Time.current).order(:start_at) }
  scope :sold_out, -> { where("LOWER(availability) LIKE ? OR LOWER(availability) LIKE ?", "%soldout%", "%closed%") }

  # Unbookable: a genuine sellout OR sales ended. Used by the list/display to
  # hide classes you can't book.
  def sold_out?
    av = availability.to_s.downcase
    av.include?("soldout") || av.include?("closed")
  end

  # Distinguish a genuine sellout (every seat booked → "SoldOut") from sales
  # merely ending ("Tickets no longer available" → "Closed", a pre-event cutoff
  # that can leave seats unsold). The report must not count a cutoff as a sellout.
  def truly_sold_out? = availability.to_s.downcase.include?("soldout")
  def sales_ended?    = availability.to_s.downcase.include?("closed")

  # Canonical status bucket for filter chips + CSS targeting.
  # "soldout" takes priority over "closed" — Lora's request: when both
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
      [ capacity - (spots_left || 0), 0 ].max
    elsif last_known_capacity.present?
      [ last_known_capacity - (last_known_spots_left || 0), 0 ].max
    elsif last_known_spots_left.present?
      # Proxy: tickets observed selling = high-water minus current
      [ last_known_spots_left - (spots_left || 0), 0 ].max
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

  # --- Revenue (face value: list price × seats) ------------------------------
  # `price` is a string like "57.00" / "1400.00". Strip any stray formatting
  # and parse; returns 0.0 for blank/free/garbage so sums stay safe.
  def price_value
    price.to_s.gsub(/[^0-9.]/, "").to_f
  end

  # Dollar value of seats sold / total / remaining. Uses tickets_sold &
  # tickets_total (with the high-water proxy fallback), so revenue inherits the
  # same "observed since tracking began" bias the % sold bars carry — it's
  # directional, not accounting-grade. nil ticket counts coerce to 0.
  def revenue_sold  = tickets_sold.to_i  * price_value
  def revenue_total = tickets_total.to_i * price_value
  def revenue_left  = revenue_total - revenue_sold

  # --- People per ticket (for grocery math) ----------------------------------
  # Most NYK classes sell 1 ticket = 1 person, but some (couples / "for two")
  # seat two people per ticket, which doubles the food. Grocery ordering needs
  # the real headcount = tickets_sold * people_per_ticket, so getting this wrong
  # under- or over-buys by 2x.
  #
  # Resolution order: a manual per-class override wins, then the signal we read
  # from the listing text, then 1. The override is keyed by `url` (the stable
  # per-class identity) and stored in Setting, NOT on this row, so it survives
  # the nightly snapshot rebuild that recreates every KitchenEvent.
  PORTION_OVERRIDE_PREFIX = "nyk:people_per_ticket:".freeze

  # Phrases NYK actually uses to say one ticket covers two people. Conservative
  # on purpose: the default is 1 and we only bump to 2 on a clear two-per-ticket
  # signal, with a human override to fix misses. "1 ticket is for 1 person" has
  # no "two" near a ticket word, so it correctly stays 1.
  TWO_PER_TICKET = Regexp.union(
    /\bfor\s+two\s+(?:people|guests|persons)\b/i,
    /\b(?:ticket|admission|registration|reservation|portion|seat)s?\b[^.]{0,40}\b(?:two|2)\b[^.]{0,20}\b(?:people|guests|persons)\b/i,
    /\bone\s+ticket\b[^.]{0,40}\btwo\b/i,
    /\bcouples?\b/i
  ).freeze

  def people_per_ticket
    portion_override || detected_people_per_ticket || 1
  end

  # The manual override (2, or 1 to force single even when the text reads as a
  # couples class), or nil when unset.
  def portion_override
    v = Setting.get("#{PORTION_OVERRIDE_PREFIX}#{url}").to_i
    v.positive? ? v : nil
  end

  def portion_overridden? = portion_override.present?

  # 2 when the listing text clearly says a ticket covers two people, else nil.
  def detected_people_per_ticket
    TWO_PER_TICKET.match?("#{name} #{description}") ? 2 : nil
  end
end
