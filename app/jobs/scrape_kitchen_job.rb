class ScrapeKitchenJob < ApplicationJob
  queue_as :default

  RECIPIENTS = ENV.fetch("KITCHEN_MAIL_TO", "botwhisperer@hey.com")

  def perform
    today  = Date.today
    months = (0..2).map { |i| (today >> i).strftime("%Y-%m") }.uniq

    # Scrape events from NY Kitchen calendar
    scraper = NyKitchenScraper.new
    events  = scraper.fetch_events(months: months)
    Rails.logger.info("ScrapeKitchenJob: fetched #{events.size} events")

    # Enrich non-sold-out events with live spot counts
    events.each do |e|
      next if NyKitchenDigestBuilder.sold_out?(e[:availability])
      next unless e[:url]

      info = scraper.fetch_availability(e[:url])
      if info
        e[:spots_left] = info[:spots_left]
        e[:capacity]   = info[:capacity]
        e[:availability] = "SoldOut" if info[:closed]
      end
      sleep 0.25
    end

    # Save snapshot (replace if already run today)
    previous = KitchenSnapshot.latest_before(today)
    snapshot = KitchenSnapshot.find_or_initialize_by(taken_on: today)
    snapshot.kitchen_events.destroy_all if snapshot.persisted?
    snapshot.save!

    events.each do |e|
      next unless e[:url]
      snapshot.kitchen_events.create!(
        url:          e[:url],
        name:         e[:name],
        start_at:     e[:start_at],
        end_at:       e[:end_at],
        price:        e[:price],
        availability: e[:availability],
        venue:        e[:venue],
        instructor:   e[:instructor],
        description:  e[:description],
        spots_left:   e[:spots_left],
        capacity:     e[:capacity],
      )
    end

    # Build digest and send email
    digest = NyKitchenDigestBuilder.build(
      current: events,
      previous_snapshot: previous,
      today: today
    )

    KitchenMailer.daily_digest(digest, recipients: RECIPIENTS).deliver_now

    Notification.notify!(
      level: "success",
      source: "kitchen_scraper",
      title: "NY Kitchen scrape complete",
      body: "#{events.size} events, #{digest[:today_events].size} today, #{digest[:tomorrow_events].size} tomorrow"
    )
  rescue => e
    Notification.notify!(
      level: "error",
      source: "kitchen_scraper",
      title: "ScrapeKitchenJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end
end
