# One QR scan: a hit on /nykitchen/r/:token before we 302 onward. Anonymous by
# design (Rich's call): counts + device/referrer, no IP, no PII.
class LinkScan < ApplicationRecord
  belongs_to :tracked_link

  scope :this_month, -> { where(scanned_at: Time.current.beginning_of_month..) }
  scope :since,      ->(t) { where(scanned_at: t..) }
  scope :for_workspace, ->(ws) {
    joins(:tracked_link).where(tracked_links: { workspace_id: ws&.id })
  }

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
