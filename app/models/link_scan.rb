# One QR scan: a hit on /nykitchen/r/:token before we 302 onward. Anonymous by
# design (Rich's call): counts + device/referrer, no IP, no PII.
class LinkScan < ApplicationRecord
  belongs_to :tracked_link

  scope :this_month, -> { where(scanned_at: Time.current.beginning_of_month..) }
  scope :since,      ->(t) { where(scanned_at: t..) }
  scope :for_workspace, ->(ws) {
    joins(:tracked_link).where(tracked_links: { workspace_id: ws&.id })
  }

  # A scan off the tasting-room monitor's calendar QR (src=display): tracked so
  # we know the screen is earning walk-in attention, but never billed.
  scope :from_display, -> { where(source: "display") }
  # A scan off a bathroom-stall poster QR (src=stall). Billed like any flyer.
  scope :from_stall, -> { where(source: "stall") }
  # Everything except the screen is a printed flyer/poster scan (the billable
  # kind: front-desk "flyer", "stall", and legacy untagged NULL). NULL-safe on
  # purpose: SQL `source != 'display'` drops NULL rows, so a plain
  # where.not(source: "display") would silently miss every untagged flyer scan.
  scope :from_flyer, -> { where("link_scans.source IS NULL OR link_scans.source != ?", "display") }

  # How a scanned QR was encountered. Printed variants are tagged at print time
  # (see display_print / display_print_stall); NULL is a legacy flyer printed
  # before per-variant tagging shipped. Only "display" (the screen) is unbilled.
  SOURCE_LABELS = {
    "display" => "Screen",
    "flyer"   => "Front-desk flyer",
    "stall"   => "Stall flyer",
  }.freeze

  def self.source_label(source)
    SOURCE_LABELS[source] || "Flyer (untagged)"
  end

  def self.billed_source?(source)
    source != "display"
  end

  # Coarse device bucket parsed from the user agent, for the scan readout.
  def self.device_bucket(user_agent)
    ua = user_agent.to_s
    case ua
    when /iPhone/i          then "iPhone"
    when /iPad/i            then "iPad"
    when /Android/i         then "Android"
    when ""                 then "Unknown"
    else                         "Other"
    end
  end
end
