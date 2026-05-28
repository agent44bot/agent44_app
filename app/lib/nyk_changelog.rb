# Reads the curated owner-facing changelog (config/nyk_changelog.yml) that
# Carson surfaces in the weekly team report. Each entry is { date:, note: }.
# Parsing failures degrade to an empty list — a malformed changelog must never
# break the email.
class NykChangelog
  PATH = Rails.root.join("config", "nyk_changelog.yml")

  def self.entries
    return [] unless File.exist?(PATH)
    raw = YAML.safe_load_file(PATH, permitted_classes: [ Date ]) || []
    Array(raw).filter_map do |e|
      next unless e.is_a?(Hash)
      note = (e["note"] || e[:note]).to_s.strip
      next if note.blank?
      date = e["date"] || e[:date]
      date = (Date.parse(date.to_s) rescue nil) unless date.is_a?(Date)
      { date: date, note: note }
    end
  rescue => e
    Rails.logger.warn("NykChangelog parse failed: #{e.class}: #{e.message}")
    []
  end

  # Entries on/after `since` (a Date), newest first, capped at `limit`.
  def self.recent(since:, limit: 6)
    entries.select { |e| e[:date] && e[:date] >= since }
           .sort_by { |e| e[:date] }.reverse.first(limit)
  end
end
