require "cgi"

module NykEventScraperHelper
  DETAIL_PAGE_PAUSE_MS = Integer(ENV["DETAIL_PAUSE_MS"] || 500)

  # Collect all unique event detail URLs from the current month grid.
  def collect_event_urls(page)
    page.evaluate(<<~JS) || []
      Array.from(
        document.querySelectorAll('.tribe-events-calendar-month__calendar-event-title-link')
      ).map(a => a.href).filter(Boolean)
    JS
  end

  # Visit a detail page and extract full event data.
  def scrape_detail_page(page, url)
    page.goto(url, timeout: 30_000, waitUntil: "domcontentloaded")
    page.wait_for_timeout(1_000)

    jsonld = extract_jsonld(page)
    avail = extract_availability(page)

    normalize_detail(url, jsonld, avail)
  end

  private

  def extract_jsonld(page)
    page.evaluate(<<~JS)
      (() => {
        const scripts = document.querySelectorAll('script[type="application/ld+json"]');
        for (const s of scripts) {
          try {
            const data = JSON.parse(s.textContent);
            const items = Array.isArray(data) ? data : [data];
            const event = items.find(i =>
              i['@type'] === 'Event' ||
              (Array.isArray(i['@type']) && i['@type'].includes('Event'))
            );
            if (event) return event;
          } catch(e) {}
        }
        return null;
      })()
    JS
  end

  def extract_availability(page)
    page.evaluate(<<~JS)
      (() => {
        const body = document.body.innerHTML;
        if (body.includes('Tickets are no longer available')) {
          return { spots_left: 0, capacity: null, closed: true };
        }
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
        if (!found) return null;
        return { spots_left: totalAvail, capacity: capKnown ? totalCap : null, closed: false };
      })()
    JS
  end

  def normalize_detail(url, jsonld, avail)
    event = { url: url }

    if jsonld
      offers = Array(jsonld["offers"]).first || {}
      location = jsonld["location"]
      location = location.first if location.is_a?(Array)
      venue = location.is_a?(Hash) ? location["name"] : nil
      performer = Array(jsonld["performer"]).first
      instructor = performer.is_a?(Hash) ? performer["name"] : nil

      event[:name]         = html_unescape(jsonld["name"])
      event[:start_at]     = jsonld["startDate"]
      event[:end_at]       = jsonld["endDate"]
      event[:price]        = offers["price"]&.to_s
      event[:availability] = (offers["availability"] || "")
                               .to_s.sub("https://schema.org/", "").sub("http://schema.org/", "")
      event[:venue]        = html_unescape(venue)
      event[:instructor]   = html_unescape(instructor)
      event[:description]  = html_unescape(jsonld["description"])
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
