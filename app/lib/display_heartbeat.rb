# Per-day presence log for the in-store Display screen (Neon), backed by a kv
# Setting — no table needed. Each heartbeat marks "the screen checked in today";
# the weekly team report uses it to say how many of the last 7 days it was live.
# We keep ~3 weeks of dates so the stored set stays tiny.
class DisplayHeartbeat
  KEY  = "nyk_display:seen_days"
  KEEP = 21

  # Mark today (or `on`) as a day the screen was live. Idempotent per day.
  def self.record!(on = Date.current)
    days = (seen_days_raw + [ on.to_s ]).uniq.sort.last(KEEP)
    Setting.set(KEY, days.to_json)
  end

  # Count of distinct days the screen was seen within [since, to].
  def self.days_seen(since:, to: Date.current)
    dates.count { |d| d >= since && d <= to }
  end

  # The earliest day we have a record for (when uptime tracking effectively
  # began), or nil if we have none yet.
  def self.tracking_since
    dates.min
  end

  def self.dates
    seen_days_raw.filter_map { |s| Date.parse(s) rescue nil }
  end

  def self.seen_days_raw
    parsed = JSON.parse(Setting.get(KEY).to_s)
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end
end
