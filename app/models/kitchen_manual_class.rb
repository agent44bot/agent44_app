# A class added by hand that isn't on nykitchen.com's events calendar: a
# private booking, a virtual class, a kids camp, a WST event the kitchen still
# has to cook for. Kept in its own table (NOT as a KitchenEvent) so the daily
# scrape, which destroy_all's + rebuilds a snapshot's events, can't wipe it.
# Merged into Sam's weekly list at read time. These aren't sold on the site, so
# there's no capacity/sold-out data.
class KitchenManualClass < ApplicationRecord
  DEFAULT_VENUE = "New York Kitchen, Canandaigua".freeze

  belongs_to :created_by, class_name: "User", optional: true
  include KitchenScoped

  validates :name, presence: true
  validates :start_at, presence: true

  # Still on the schedule: not yet ended (falls back to start_at when no end).
  scope :upcoming, -> { where("COALESCE(end_at, start_at) >= ?", Time.current).order(:start_at) }

  def venue_label
    venue.presence || DEFAULT_VENUE
  end

  # Stable key for the recipe-packet system (KitchenPacketLink is keyed by
  # event_url). Unlike a scraped class this has no nykitchen.com URL, so we use a
  # synthetic one tied to the row. Persistent, so a packet Caitlin builds stays
  # attached. (The controller deletes the link on destroy, so a reused id can't
  # inherit an old class's packet.)
  def packet_url
    "manual-#{id}"
  end

  # True when packet_url points at a hand-added class rather than a scraped one.
  def self.packet_url?(url)
    url.to_s.start_with?("manual-")
  end

  # The row id embedded in a packet_url ("manual-12" -> 12), or nil.
  def self.id_from_packet_url(url)
    url.to_s.delete_prefix("manual-").then { |s| s.match?(/\A\d+\z/) ? s.to_i : nil }
  end

  # --- Enough of KitchenEvent's shape for the pull sheet -------------------
  # KitchenAi::GroceryList does its math against a scraped event (url,
  # tickets_sold, people_per_ticket, portion_overridden?). A hand-added class
  # has no ticket data at all, so expected_headcount stands in for the room:
  # one "ticket" per person, never an override. Without these the pull sheet
  # silently skipped every private class.

  def url = packet_url

  def tickets_sold = expected_headcount.to_i

  def people_per_ticket = 1

  def portion_overridden? = false

  # Same shape and math as KitchenEvent#default_station_counts, off
  # expected_headcount instead of ticket sales: two people per station, at least
  # one, and never pre-set to doubles.
  def default_station_counts
    KitchenEvent::StationCounts.new(doubles: 0, singles: [ (tickets_sold / 2.0).ceil, 1 ].max, set: false)
  end

  # No headcount entered yet, so the sheet can say so instead of quietly
  # shopping for a single station.
  def headcount_missing? = expected_headcount.to_i.zero?
end
