# A class/camp added by hand (e.g. Lora's kids camps) that isn't on
# nykitchen.com's events calendar. Kept in its own table — NOT as a
# KitchenEvent — so the daily scrape (which destroy_all's + rebuilds a
# snapshot's events) can't wipe it. Merged into Sam's weekly list at read
# time. Camps aren't ticketed, so there's no capacity/sold-out data.
class KitchenManualClass < ApplicationRecord
  DEFAULT_VENUE = "New York Kitchen, Canandaigua".freeze

  belongs_to :created_by, class_name: "User", optional: true

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
  # inherit an old camp's packet.)
  def packet_url
    "manual-#{id}"
  end
end
