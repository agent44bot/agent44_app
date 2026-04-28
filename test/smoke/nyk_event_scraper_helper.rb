require "cgi"

module NykEventScraperHelper
  DETAIL_PAGE_PAUSE_MS = Integer(ENV["DETAIL_PAUSE_MS"] || 2_000)

  # Collect all unique event detail URLs from the current month grid.
  def collect_event_urls(page)
    page.evaluate(<<~JS) || []
      Array.from(
        document.querySelectorAll('.tribe-events-calendar-month__calendar-event-title-link')
      ).map(a => a.href).filter(Boolean)
    JS
  end

  # Visit a detail page and extract full event data from DOM + ticket widget.
  # Returns nil if the event has been pulled from the site (404, or grid still
  # links to a deleted post — TEC's caches lag the actual post deletion).
  def scrape_detail_page(page, url)
    response = page.goto(url, timeout: 30_000, waitUntil: "domcontentloaded")
    page.wait_for_timeout(1_000)

    status = (response&.status rescue nil).to_i
    return nil if status >= 400
    # Belt-and-suspenders: WP sometimes returns 200 with a "page not found" body.
    # If the event-title element isn't on the page, treat it as deleted.
    return nil unless page.locator("h1.tribe-events-single-event-title").count > 0

    # Scroll ticket section into view so video captures availability info
    page.evaluate("(document.querySelector('.tribe-tickets') || document.querySelector('.tribe-events-content') || document.body).scrollIntoView({behavior: 'smooth', block: 'center'})")
    page.wait_for_timeout(400)
    page.evaluate("window.scrollBy({top: Math.round(window.innerHeight * 0.3), behavior: 'smooth'})")
    page.wait_for_timeout(600)

    event_data = extract_event_from_dom(page)
    avail = extract_availability(page)

    normalize_detail(url, event_data, avail)
  end

  private

  # Scrape event fields directly from the detail page DOM.
  # The Events Calendar plugin uses consistent class names across event pages.
  def extract_event_from_dom(page)
    page.evaluate(<<~JS)
      (() => {
        const text = (sel) => {
          const el = document.querySelector(sel);
          return el ? el.textContent.trim() : null;
        };

        // Check if the event has passed (banner at top of past events)
        const passed = !!document.body.innerText.match(/this event has passed/i);

        // Title
        const name = text('h1.tribe-events-single-event-title');

        // Date string: "Sunday May 31 @ 11:00 am - 1:00 pm"
        const dateText = text('.tribe-events-schedule');

        // Start date from abbr title attribute (YYYY-MM-DD)
        const startAbbr = document.querySelector('.tribe-events-abbr');
        const startDate = startAbbr ? startAbbr.getAttribute('title') : null;

        // Parse start/end times from dateText to build full ISO timestamps
        let startAt = startDate;
        let endAt = null;
        if (dateText && startDate) {
          const timeMatch = dateText.match(/(\\d{1,2}:\\d{2}\\s*[ap]m)\\s*-\\s*(\\d{1,2}:\\d{2}\\s*[ap]m)/i);
          if (timeMatch) {
            const parseTime = (t) => {
              const m = t.trim().match(/(\\d{1,2}):(\\d{2})\\s*([ap]m)/i);
              if (!m) return null;
              let h = parseInt(m[1]);
              const min = m[2];
              const ampm = m[3].toLowerCase();
              if (ampm === 'pm' && h !== 12) h += 12;
              if (ampm === 'am' && h === 12) h = 0;
              return String(h).padStart(2, '0') + ':' + min + ':00';
            };
            const st = parseTime(timeMatch[1]);
            const et = parseTime(timeMatch[2]);
            if (st) startAt = startDate + 'T' + st;
            if (et) endAt = startDate + 'T' + et;
          }
        }

        // Price from ticket widget
        const priceEl = document.querySelector('.tribe-amount');
        const price = priceEl ? priceEl.textContent.trim().replace(/[^0-9.]/g, '') : null;

        // Venue
        const venue = text('.tribe-venue a') || text('.tribe-venue');

        // Description (just the content paragraphs, skip headings)
        const descEl = document.querySelector('.tribe-events-content');
        const description = descEl ? descEl.textContent.trim().substring(0, 500) : null;

        // Event image: og:image meta tag or featured image in content
        const ogImage = document.querySelector('meta[property="og:image"]');
        const imageUrl = ogImage ? ogImage.getAttribute('content') : null;

        return { name, startAt, endAt, price, venue, description, passed, imageUrl };
      })()
    JS
  end

  def extract_availability(page)
    page.evaluate(<<~JS)
      (() => {
        const body = document.body.innerHTML;

        // Check for "Tickets are no longer available" in the ticket section
        const hasClosed = body.includes('Tickets are no longer available');

        // Check for "SOLD OUT" only in the event's own content (header + ticket area),
        // NOT the "More Classes You Might Like" recommendations at the bottom.
        const eventContent = document.querySelector('.tribe-events-single-event-title, .tribe-events-schedule, .tribe-tickets, .tribe-events-content');
        const mainArea = document.querySelector('.tribe-events-single');
        // The recommendations section has class "tribe-related-events" — exclude it
        let eventText = '';
        if (mainArea) {
          const clone = mainArea.cloneNode(true);
          const related = clone.querySelector('.tribe-related-events, .tribe-events-related-events-title');
          if (related) related.parentNode.removeChild(related);
          eventText = clone.innerText || clone.textContent || '';
        } else {
          eventText = (eventContent ? eventContent.textContent : '') || '';
        }
        const hasSoldOut = /sold\s*out/i.test(eventText);

        // If "SOLD OUT" appears in the event's own content, prefer that over "closed"
        if (hasClosed && !hasSoldOut) {
          return { spots_left: 0, capacity: null, closed: true };
        }
        if (hasSoldOut && hasClosed) {
          return { spots_left: 0, capacity: null, closed: false };
        }

        // Strategy 1: data attributes on ticket items (some events use these)
        const items = document.querySelectorAll('[class*="tribe-tickets__tickets-item"]');
        let totalAvail = 0, totalCap = 0, capKnown = true, found = false;
        const seenPools = new Set();
        items.forEach(item => {
          const avail = parseInt(item.getAttribute('data-available-count'));
          if (isNaN(avail)) return;
          found = true;
          const cap = parseInt(item.getAttribute('data-shared-cap'));
          const shared = item.getAttribute('data-has-shared-cap') === 'true';
          if (shared && !isNaN(cap)) {
            if (!seenPools.has(cap)) {
              seenPools.add(cap);
              totalAvail += avail;
              totalCap += cap;
            }
          } else {
            totalAvail += avail;
            if (!isNaN(cap)) { totalCap += cap; } else { capKnown = false; }
          }
        });
        if (found) {
          return { spots_left: totalAvail, capacity: capKnown ? totalCap : null, closed: false };
        }

        // Strategy 2: parse "X available" text from ticket section
        const ticketSection = document.querySelector('.tribe-tickets, .tribe-tickets__tickets-wrapper');
        if (ticketSection) {
          const text = ticketSection.textContent;
          const availMatch = text.match(/(\\d+)\\s+available/i);
          if (availMatch) {
            return { spots_left: parseInt(availMatch[1]), capacity: null, closed: false };
          }
          // Has a ticket section but no availability text — likely sold out or free
          if (text.includes('Sold Out') || text.includes('sold out')) {
            return { spots_left: 0, capacity: null, closed: false };
          }
        }

        return null;
      })()
    JS
  end

  def normalize_detail(url, dom_data, avail)
    event = { url: url }

    if dom_data
      event[:name]        = html_unescape(dom_data["name"])
      event[:start_at]    = dom_data["startAt"]
      event[:end_at]      = dom_data["endAt"]
      event[:price]       = dom_data["price"]
      event[:venue]       = html_unescape(dom_data["venue"])
      event[:description] = html_unescape(dom_data["description"])
      event[:image_url]   = dom_data["imageUrl"]
      event[:passed]      = dom_data["passed"]
    end

    if avail
      event[:spots_left] = avail["spots_left"]
      event[:capacity]   = avail["capacity"]
      if avail["closed"]
        event[:availability] = "Closed"
      elsif avail["spots_left"] && avail["spots_left"] > 0
        event[:availability] = "InStock"
      elsif avail["spots_left"] == 0
        event[:availability] = "SoldOut"
      end
    end

    event
  end

  def html_unescape(s)
    s ? CGI.unescapeHTML(s.to_s) : nil
  end
end
