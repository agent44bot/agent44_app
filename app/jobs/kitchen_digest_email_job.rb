class KitchenDigestEmailJob < ApplicationJob
  queue_as :default

  # Fallback if the NY Kitchen workspace or its members can't be resolved, so a
  # data hiccup never silently drops the digest for the two core recipients.
  FALLBACK_RECIPIENTS = [ "botwhisperer@hey.com", "lora.downie@nykitchen.com" ].freeze

  # Members of the NY Kitchen workspace who still have the daily digest on.
  # New members get it by default; anyone can opt out in Settings.
  def self.recipients
    Workspace.find_by(slug: "nykitchen")&.daily_digest_recipients.presence || FALLBACK_RECIPIENTS
  end

  # One-off personal note shown at the top of a single day's digest (e.g. Rich
  # congratulating the team after a class). Edited at /admin/digest_note. It
  # only renders on its date, so it expires on its own.
  NOTE_KEY             = "nyk_digest:note".freeze
  NOTE_ON_KEY          = "nyk_digest:note_on".freeze
  NOTE_HEADING_KEY     = "nyk_digest:note_heading".freeze
  DEFAULT_NOTE_HEADING = "A note from our human, Rich".freeze

  def self.note_for(day)
    Setting.get(NOTE_KEY).presence if Setting.get(NOTE_ON_KEY) == day.iso8601
  end

  def self.note_heading
    Setting.get(NOTE_HEADING_KEY).presence || DEFAULT_NOTE_HEADING
  end

  # Digest payload for `today`, or nil when there are no snapshots at all.
  # Shared by #perform and the admin "send me a test" button.
  def self.build_digest(today)
    # Prefer today's snapshot, but fall back to the most recent one we have.
    # The 9 AM smoke that produces today's snapshot has been failing
    # intermittently, and skipping the digest entirely on those days is
    # worse for Lora than showing yesterday's data with a clear note.
    snapshot = KitchenSnapshot.find_by(taken_on: today) || KitchenSnapshot.latest
    return unless snapshot

    previous = KitchenSnapshot.latest_before(snapshot.taken_on)

    events = snapshot.kitchen_events.map do |e|
      {
        url: e.url, name: e.name, start_at: e.start_at, end_at: e.end_at,
        price: e.price, availability: e.availability, venue: e.venue,
        instructor: e.instructor, description: e.description,
        spots_left: e.spots_left, capacity: e.capacity,
        last_known_spots_left: e.last_known_spots_left,
        last_known_capacity: e.last_known_capacity
      }
    end

    digest = NyKitchenDigestBuilder.build(
      current: events,
      previous_snapshot: previous,
      today: today
    )
    digest[:snapshot_date] = snapshot.taken_on
    digest[:stale_data]    = snapshot.taken_on != today
    [ digest, snapshot ]
  end

  def perform
    today    = Date.today
    digest, snapshot = self.class.build_digest(today)
    unless digest
      Rails.logger.info("KitchenDigestEmailJob: no snapshots in DB at all, skipping")
      return
    end

    # Mondays: prepend the Carson weekly team report (one combined email). The
    # builder makes the single paid Carson call; the other six days skip it.
    weekly = if today.monday?
      WeeklySalesEmailJob.build_summary(snapshot)
    end

    recipients = self.class.recipients
    KitchenMailer.daily_digest(digest, recipients: recipients, weekly_report: weekly, note: self.class.note_for(today), note_heading: self.class.note_heading).deliver_now

    # Stamp the weekly report's send time so the Analyst dashboard's recipient
    # engagement panel keeps measuring dashboard visits after Monday's report.
    Setting.touch_time("nyk_weekly_report:last_sent_at") if weekly

    Rails.logger.info("KitchenDigestEmailJob: sent to #{recipients} (snapshot #{snapshot.taken_on}, weekly_report: #{!weekly.nil?})")
  rescue => e
    Notification.notify!(
      level: "error",
      source: "kitchen_email",
      title: "KitchenDigestEmailJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end
end
