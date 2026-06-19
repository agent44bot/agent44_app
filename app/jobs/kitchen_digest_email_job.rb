class KitchenDigestEmailJob < ApplicationJob
  queue_as :default

  RECIPIENTS = [ "botwhisperer@hey.com", "lora.downie@nykitchen.com" ]

  def perform
    today    = Date.today
    # Prefer today's snapshot, but fall back to the most recent one we have.
    # The 9 AM smoke that produces today's snapshot has been failing
    # intermittently, and skipping the digest entirely on those days is
    # worse for Lora than showing yesterday's data with a clear note.
    snapshot = KitchenSnapshot.find_by(taken_on: today) || KitchenSnapshot.latest

    unless snapshot
      Rails.logger.info("KitchenDigestEmailJob: no snapshots in DB at all, skipping")
      return
    end

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

    # Mondays: prepend the Carson weekly team report (one combined email). The
    # builder makes the single paid Carson call; the other six days skip it.
    weekly = if today.monday?
      WeeklySalesEmailJob.build_summary(snapshot)
    end

    KitchenMailer.daily_digest(digest, recipients: RECIPIENTS, weekly_report: weekly).deliver_now

    # Stamp the weekly report's send time so the Analyst dashboard's recipient
    # engagement panel keeps measuring dashboard visits after Monday's report.
    Setting.touch_time("nyk_weekly_report:last_sent_at") if weekly

    Rails.logger.info("KitchenDigestEmailJob: sent to #{RECIPIENTS} (snapshot #{snapshot.taken_on}, weekly_report: #{!weekly.nil?})")
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
