# Preview at http://localhost:3000/rails/mailers/kitchen_mailer/daily_digest
class KitchenMailerPreview < ActionMailer::Preview
  def daily_digest
    today    = Date.today
    snapshot = KitchenSnapshot.find_by(taken_on: today) || KitchenSnapshot.latest
    return unless snapshot

    previous = KitchenSnapshot.latest_before(snapshot.taken_on)
    events = snapshot.kitchen_events.map do |e|
      { url: e.url, name: e.name, start_at: e.start_at, end_at: e.end_at,
        price: e.price, availability: e.availability, venue: e.venue,
        instructor: e.instructor, description: e.description,
        spots_left: e.spots_left, capacity: e.capacity,
        last_known_spots_left: e.last_known_spots_left,
        last_known_capacity: e.last_known_capacity }
    end

    digest = NyKitchenDigestBuilder.build(current: events, previous_snapshot: previous, today: today)
    digest[:snapshot_date]   = snapshot.taken_on
    digest[:stale_data]      = snapshot.taken_on != today
    digest[:selling_fastest] = KitchenSnapshot.selling_fastest(snapshot: snapshot)
    digest[:needs_a_push]    = KitchenSnapshot.needs_a_push(snapshot: snapshot)

    KitchenMailer.daily_digest(digest, recipients: [ "preview@example.com" ])
  end

  # Preview at http://localhost:3000/rails/mailers/kitchen_mailer/weekly_sales
  # Uses the exact same summary builder as the scheduled Sunday send (incl.
  # Carson's AI intro — one API call per load).
  def weekly_sales
    snapshot = KitchenSnapshot.latest
    return unless snapshot

    # carson: false — this mailer preview is for eyeballing layout; don't burn a
    # Claude call (Carson's intro) every time it's viewed.
    KitchenMailer.weekly_sales(WeeklySalesEmailJob.build_summary(snapshot, carson: false), recipients: [ "preview@example.com" ])
  end
end
