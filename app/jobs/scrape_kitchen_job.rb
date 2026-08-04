class ScrapeKitchenJob < ApplicationJob
  queue_as :default

  # force: re-scrape and replace today's snapshot even though one already
  # exists. The daily run is the only writer otherwise, so a class pulled from
  # nykitchen.com mid-morning would keep printing on the flyer until tomorrow.
  # This is what the flyer's "Refresh classes" button calls.
  def perform(force: false)
    today  = Date.today

    # Skip if Playwright already created today's snapshot (GHA runs at ~9:47 AM)
    if KitchenSnapshot.exists?(taken_on: today) && !force
      Rails.logger.info("ScrapeKitchenJob: snapshot already exists for #{today}, skipping")
      return
    end

    months = (0..2).map { |i| (today >> i).strftime("%Y-%m") }.uniq

    # Scrape events from NY Kitchen calendar
    scraper = NyKitchenScraper.new
    events  = scraper.fetch_events(months: months)
    Rails.logger.info("ScrapeKitchenJob: fetched #{events.size} events")

    # A zero-event scrape means the calendar structure changed (e.g. the source
    # URL moved and now 404s), not that NY Kitchen has no classes. Writing an
    # empty snapshot would clobber the last good data and, via the taken_on
    # guard above, block retries for the rest of the day. Alert and bail instead
    # of silently reporting "0 events scraped" as a success.
    if events.empty?
      Notification.notify!(
        level: "error",
        source: "kitchen_scraper",
        title: "NY Kitchen scrape returned 0 events",
        body: "fetch_events came back empty for #{months.join(', ')} - the calendar page likely moved or changed markup. No snapshot written; last good snapshot left in place.",
        telegram: true
      )
      return
    end

    # Enrich all events with live spot counts from detail pages
    # (JSON-LD availability from the calendar can be stale/wrong)
    events.each do |e|
      next unless e[:url]

      info = scraper.fetch_availability(e[:url])
      if info
        e[:spots_left] = info[:spots_left]
        e[:capacity]   = info[:capacity]
        # Detail-page image as a fallback when the calendar JSON-LD
        # didn't include one (which is currently always).
        e[:image_url] ||= info[:image_url]
        e[:menu] = info[:menu]
        if info[:closed]
          e[:availability] = "Closed"
          e[:closed] = true
        elsif info[:spots_left] && info[:spots_left] > 0
          e[:availability] = "InStock"
        elsif info[:spots_left] == 0
          e[:availability] = "SoldOut"
        end
      end
      sleep 0.25
    end

    # Save snapshot (replace if already run today)
    previous = KitchenSnapshot.latest_before(today)
    prev_events = previous ? previous.kitchen_events.index_by(&:url) : {}
    snapshot = KitchenSnapshot.find_or_initialize_by(taken_on: today)
    snapshot.kitchen_events.destroy_all if snapshot.persisted?
    snapshot.save!

    events.each do |e|
      next unless e[:url]

      # Carry forward last-known ticket data from previous snapshot
      prev = prev_events[e[:url]]

      # "Tickets no longer available" zeroes the live page (spots 0, no price) —
      # that's a pre-event sales cutoff, not a sellout. Carry forward the last
      # real observation so the class isn't mistaken for a sellout, doesn't inject
      # a phantom booking, and keeps its price. EXCEPT: if the class was truly
      # sold out before, it stays sold out (don't resurrect it with old spots_left).
      if e[:closed] && prev
        if prev.truly_sold_out?
          # Was sold out; stays sold out (don't carry forward old spots)
          e[:availability] = "SoldOut"
          # Zero out the spots (they're invalid after true sellout)
          e[:spots_left] = 0
          e[:capacity] = prev.capacity
        else
          # Was a pre-event cutoff; restore the last observation
          e[:spots_left]   = prev.spots_left
          e[:capacity]     = prev.capacity
          e[:availability] = "Closed"
        end
        e[:price] = prev.price if e[:price].blank?
      end

      if e[:spots_left] && e[:capacity]
        last_spots = e[:spots_left]
        last_cap   = e[:capacity]
      elsif prev
        last_spots = prev.last_known_spots_left || prev.spots_left
        last_cap   = prev.last_known_capacity || prev.capacity
      end

      e[:last_known_spots_left] = last_spots
      e[:last_known_capacity]   = last_cap

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
        menu:         e[:menu],
        image_url:    e[:image_url],
        spots_left:   e[:spots_left],
        capacity:     e[:capacity],
        last_known_spots_left: last_spots,
        last_known_capacity:   last_cap,
      )
    end

    Notification.notify!(
      level: "success",
      source: "kitchen_scraper",
      title: "NY Kitchen scrape complete",
      body: "#{events.size} events scraped"
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
