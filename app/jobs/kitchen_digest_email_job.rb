class KitchenDigestEmailJob < ApplicationJob
  queue_as :default

  RECIPIENTS = [ "botwhisperer@hey.com", "lora.downie@nykitchen.com" ]

  def perform
    today    = Date.today
    snapshot = KitchenSnapshot.find_by(taken_on: today)
    previous = KitchenSnapshot.latest_before(today)

    unless snapshot
      Rails.logger.info("KitchenDigestEmailJob: no snapshot for #{today}, skipping")
      return
    end

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

    KitchenMailer.daily_digest(digest, recipients: RECIPIENTS).deliver_now

    Rails.logger.info("KitchenDigestEmailJob: sent to #{RECIPIENTS}")
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
