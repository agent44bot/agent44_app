require "net/http"
require "nokogiri"
require "json"
require "cgi"

class NyKitchenScraper
  # The calendar page. No longer scraped for the event list (see REST_API), but
  # still the Referer we present on requests, and the human-facing URL.
  BASE = "https://nykitchen.com/calendar/"

  # The Events Calendar's REST API returns the same events as structured JSON,
  # which is what the listing now reads. Scraping the month view's JSON-LD was
  # fragile: SiteGround's CAPTCHA intermittently served a challenge page instead
  # of the calendar, and the markup shifted under us.
  REST_API = "https://nykitchen.com/wp-json/tribe/events/v1/events"
  UA   = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

  # Fetch events using Tribe Events REST API.
  # This is much more reliable than HTML scraping since it gets structured data.
  def fetch_events(months:)
    seen = {}

    # For each month, query the API for events in that range
    months.each do |ym|
      # Parse YYYY-MM to get start and end dates
      year, month = ym.split("-")
      start_date = "#{year}-#{month}-01"
      # Last day of month
      last_day = Date.parse(start_date).next_month.prev_day.day
      end_date = "#{year}-#{month}-#{last_day}"

      per_page = 100
      page = 1
      loop do
        # Query REST API with date range and pagination
        url = "#{REST_API}?per_page=#{per_page}&page=#{page}&start_date=#{start_date}&end_date=#{end_date}"
        response_data = fetch_rest_api(url)
        break if response_data.nil?

        events = response_data.dig("events") || []
        break if events.empty?

        # Normalize each event and add to seen
        events.each do |raw_event|
          normalized = normalize_tribe_event(raw_event)
          if normalized
            key = normalized[:url] || "#{normalized[:name]}|#{normalized[:start_at]}"
            unless seen.key?(key)
              seen[key] = normalized
            end
          end
        end

        # Check if there are more pages
        # The API reports total_pages, so use it rather than inferring the end
        # from a short page: The Events Calendar has historically capped
        # per_page below what was requested, which would end the loop after
        # page 1 and silently drop the rest of a busy month.
        total_pages = response_data["total_pages"].to_i
        break if total_pages.positive? && page >= total_pages
        break if total_pages.zero? && events.size < per_page

        page += 1
        break if page > 50  # Safety limit
      end
    end

    seen.values
  end

  # Scrape an event detail page for live ticket availability + image + menu.
  # Returns { spots_left:, capacity:, closed:, image_url:, menu: } or nil.
  def fetch_availability(url)
    return nil if url.nil? || url.empty?
    html = get(url)
    return nil unless html

    image_url  = extract_event_image(html)
    menu       = extract_event_menu(html)
    # The REST listing carries no organizer (it is [] on every event), so the
    # instructor now comes off the detail page's JSON-LD performer instead.
    instructor = extract_instructor(html)

    if html.include?("Tickets are no longer available")
      return { spots_left: 0, capacity: nil, closed: true, image_url: image_url, menu: menu, instructor: instructor }
    end

    # A sold-out class drops its data-available-count attributes and its price,
    # so the ticket-block parse below finds nothing and would return nil (leaving
    # availability blank/stale). The detail page's own JSON-LD still reports
    # "SoldOut" reliably, so trust it as a fallback signal.
    sold_out = detail_json_ld_sold_out?(html)

    blocks = html.split(/class="[^"]*tribe-tickets__tickets-item[ "][^"]*"/)[1..] || []
    by_id     = {}
    seen_pool = {}

    blocks.each do |blk|
      head = blk[0, 4000]
      tid    = head[/data-ticket-id="(\d+)"/, 1]
      avail  = head[/data-available-count="(\d+)"/, 1]&.to_i
      avail ||= head[/tribe-tickets__tickets-item-extra-available-quantity[^>]*>\s*(\d+)\s*</, 1]&.to_i
      next unless avail

      cap    = head[/data-shared-cap="(\d+)"/, 1]&.to_i
      shared = head.include?('data-has-shared-cap="true"')
      key = tid || "#{avail}-#{cap}-#{shared}"
      by_id[key] ||= { avail: avail, cap: cap, shared: shared }
    end

    if by_id.empty?
      return { spots_left: 0, capacity: nil, image_url: image_url, menu: menu, instructor: instructor } if sold_out
      return nil
    end

    spots_left = 0
    capacity   = 0
    cap_known  = true

    by_id.each_value do |t|
      if t[:shared] && t[:cap]
        unless seen_pool.key?(t[:cap])
          seen_pool[t[:cap]] = true
          spots_left += t[:avail]
          capacity   += t[:cap]
        end
      else
        spots_left += t[:avail]
        if t[:cap]
          capacity += t[:cap]
        else
          cap_known = false
        end
      end
    end

    { spots_left: spots_left, capacity: cap_known ? capacity : nil, image_url: image_url, menu: menu, instructor: instructor }
  end

  # The instructor, from the detail page's JSON-LD Event performer.
  def extract_instructor(html)
    extract_jsonld_events(html).each do |raw|
      # Careful: Array(hash) splits it into key/value pairs rather than wrapping
      # it, so a single performer object has to be handled before the Array cast.
      perf = raw["performer"]
      perf = perf.first if perf.is_a?(Array)
      name = perf.is_a?(Hash) ? perf["name"] : perf
      return decode(name.to_s).strip.presence if name.present?
    end
    nil
  end

  # The class menu from the detail page: an <h3 class="nyk-event-meta-title">
  # heading reading "Menu" followed by <p> item lines, between the price block
  # and the disclosures link. Returns the joined item text or nil.
  def extract_event_menu(html)
    m = html.match(%r{<h[23][^>]*class="[^"]*nyk-event-meta-title[^"]*"[^>]*>\s*Menu\s*</h[23]>(.*?)(?:<h[23]|<a\s|</div>)}mi)
    return nil unless m
    items = m[1].scan(%r{<p[^>]*>(.*?)</p>}mi).flatten
    text = items.map { |t| CGI.unescapeHTML(t.gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip }
                .reject(&:blank?).join(" / ")
    text.presence&.slice(0, 500)
  end

  # Pull the event page's primary image. Priority:
  #   1. JSON-LD #primaryimage — the WordPress *featured* image. Most accurate
  #      per event. og:image alone is unreliable: when no social image is set,
  #      Yoast falls back to the site-default building shot (GTP_NYK-OUTDOORS),
  #      which is the wrong image for the class.
  #   2. og:image meta tag
  #   3. twitter:image meta tag
  #   4. image field on a JSON-LD Event block
  def extract_event_image(html)
    if (primary = extract_primary_image(html))
      return primary
    end
    if (m = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i)) ||
       (m = html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i))
      return m[1]
    end
    if (m = html.match(/<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i))
      return m[1]
    end
    extract_jsonld_events(html).each do |raw|
      img = Array(raw["image"]).first || raw["image"]
      url = img.is_a?(Hash) ? img["url"] : img.to_s.presence
      return url if url
    end
    nil
  end

  # Resolve the JSON-LD ImageObject whose @id ends in "#primaryimage" (Yoast's
  # designated featured image for the page) to its url. Parsed, so field order
  # doesn't matter. Returns nil when the page has no such node.
  def extract_primary_image(html)
    html.scan(%r{<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>}m).each do |(json)|
      data = JSON.parse(json) rescue next
      nodes = []
      (data.is_a?(Array) ? data : [ data ]).each do |d|
        next unless d.is_a?(Hash)
        nodes.concat(Array(d["@graph"]))
        nodes << d
      end
      img = nodes.find do |n|
        n.is_a?(Hash) && Array(n["@type"]).include?("ImageObject") &&
          n["@id"].to_s.end_with?("#primaryimage") && n["url"].to_s.strip.present?
      end
      return img["url"].strip if img
    end
    nil
  end

  private

  # WordPress serializes these fields HTML-escaped.
  def decode(value)
    value && CGI.unescapeHTML(value.to_s)
  end

  def fetch_rest_api(url)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"]      = UA
    request["Accept"]          = "application/json"
    request["Referer"]         = "https://nykitchen.com/calendar/"
    request["Origin"]          = "https://nykitchen.com"
    request["Accept-Language"] = "en-US,en;q=0.9"

    response = http.request(request)
    code = response.code.to_i

    body = response.body.force_encoding("UTF-8").scrub

    unless code.between?(200, 299)
      Rails.logger.warn("NyKitchenScraper REST API: #{url} -> HTTP #{code}")
      Rails.logger.warn("NyKitchenScraper REST API response body: #{body.slice(0, 500)}")
      return nil
    end

    data = JSON.parse(body) rescue nil

    if data && data.is_a?(Hash) && data["events"].is_a?(Array)
      Rails.logger.info("NyKitchenScraper REST API: #{url} -> #{data['events'].size} events")
    else
      Rails.logger.warn("NyKitchenScraper REST API: #{url} -> Invalid JSON response")
      Rails.logger.warn("NyKitchenScraper REST API response: #{body.slice(0, 1000)}")
    end

    data
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    Rails.logger.warn("NyKitchenScraper REST API: #{url} -> #{e.class}: #{e.message}")
    nil
  end

  def get(url)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"]      = UA
    request["Accept"]          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    request["Accept-Language"] = "en-US,en;q=0.9"

    response = http.request(request)
    code = response.code.to_i
    unless code.between?(200, 299)
      Rails.logger.warn("NyKitchenScraper: #{url} -> HTTP #{code}")
      return nil
    end

    body = response.body.force_encoding("UTF-8").scrub
    body
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    Rails.logger.warn("NyKitchenScraper: #{url} -> #{e.class}: #{e.message}")
    nil
  end

  def extract_jsonld_events(html)
    events = []
    html.scan(%r{<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>}m).each do |(json)|
      data = JSON.parse(json) rescue next
      Array(data).flatten.each do |item|
        next unless item.is_a?(Hash)
        types = Array(item["@type"])
        events << item if types.include?("Event")
      end
    end
    events
  end

  # True when any Event offer on the detail page reports schema.org SoldOut.
  # Used as a fallback when the ticket widget exposes no live seat count.
  def detail_json_ld_sold_out?(html)
    extract_jsonld_events(html).any? do |raw|
      offers = raw["offers"]
      offers = [ offers ] unless offers.is_a?(Array)
      offers.any? { |o| o.is_a?(Hash) && o["availability"].to_s.include?("SoldOut") }
    end
  end

  # The REST API names its fields differently from the JSON-LD the listing used
  # to read: start_date not startDate, title not name, and image is a hash
  # rather than a string.
  def normalize_tribe_event(raw)
    # The API reports naive local times ("2026-08-10 18:00:00") with no offset.
    # DateTime.parse would read those as UTC and shift every class four hours
    # earlier, so a 6pm class shows as 2pm. Time.zone.parse reads them in the
    # app zone (Eastern), which is the zone the site publishes in.
    start = raw["start_date"] && (Time.zone.parse(raw["start_date"]) rescue nil)
    return nil unless start

    # Titles and descriptions come back HTML-escaped the same way cost does:
    # "Chef&#8217;s Table", "Summer Pasta Party &#8211; Gnocchi". Left encoded
    # they render as literal entities in the digest email and admin cards.
    title = decode(raw["title"])&.strip
    return nil unless title

    image_url = raw["image"]["url"] if raw["image"].is_a?(Hash)

    # Cost arrives HTML-escaped, e.g. "&#36;85". It has to be unescaped before
    # the currency symbol is stripped: peeling off "&", "#" and ";" first leaves
    # the entity's digits behind and turns "&#36;85" into "3685".
    price = raw["cost"].presence&.then { |c| CGI.unescapeHTML(c.to_s).gsub(/[$\s]/, "").strip }

    {
      url: raw["url"] || raw["link"],
      name: title,
      start_at: start,
      end_at: (Time.zone.parse(raw["end_date"]) rescue nil),
      price: price,
      availability: "InStock", # refined later by fetch_availability
      venue: "New York Kitchen",
      description: decode(raw["description"])&.strip,
      image_url: image_url
    }
  end
end
