require "net/http"
require "nokogiri"
require "json"
require "cgi"

class NyKitchenScraper
  # Use Tribe Events REST API instead of HTML scraping
  REST_API = "https://nykitchen.com/wp-json/tribe/events/v1/events"
  UA   = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

  # Fetch events using Tribe Events REST API.
  # This is much more reliable than HTML scraping since it gets structured data.
  def fetch_events(months:)
    seen = {}
    
    # For each month, query the API for events in that range
    months.each do |ym|
      # Parse YYYY-MM to get start and end dates
      year, month = ym.split('-')
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
        
        events = response_data.dig('events') || []
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
        break if events.size < per_page  # If less than per_page, we got all results
        
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

    image_url = extract_event_image(html)
    menu      = extract_event_menu(html)

    if html.include?("Tickets are no longer available")
      return { spots_left: 0, capacity: nil, closed: true, image_url: image_url, menu: menu }
    end

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

    return nil if by_id.empty?

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

    { spots_left: spots_left, capacity: cap_known ? capacity : nil, image_url: image_url, menu: menu }
  end

  def extract_event_menu(html)
    m = html.match(%r{<h[23][^>]*class="[^"]*nyk-event-meta-title[^"]*"[^>]*>\s*Menu\s*</h[23]>(.*?)(?:<h[23]|<a\s|</div>)}mi)
    return nil unless m
    items = m[1].scan(%r{<p[^>]*>(.*?)</p>}mi).flatten
    text = items.map { |t| CGI.unescapeHTML(t.gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip }
                .reject(&:blank?).join(" / ")
    text.presence&.slice(0, 500)
  end

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
    nil
  end

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
    
    if data && data.is_a?(Hash) && data['events'].is_a?(Array)
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

  def normalize_tribe_event(raw)
    # Tribe Events REST API returns events with different field names than JSON-LD
    # Example: start_date instead of startDate, title instead of name, image is a hash with {url: ...}
    
    start = raw["start_date"] && (DateTime.parse(raw["start_date"]) rescue nil)
    return nil unless start

    title = raw["title"]&.strip
    return nil unless title

    url = raw["url"] || raw["link"]
    
    # Extract image URL from nested image hash
    image_url = nil
    if raw["image"].is_a?(Hash)
      image_url = raw["image"]["url"]
    end
    
    # Extract cost and remove HTML entities
    price = raw["cost"]&.to_s
    price = price.gsub(/[&#\$;]/, "").strip if price
    
    {
      url: url,
      name: title,
      start_at: start.to_time,
      end_at: (DateTime.parse(raw["end_date"]).to_time rescue nil),
      price: price,
      availability: "InStock",  # Will be updated by fetch_availability
      venue: "New York Kitchen",
      description: raw["description"]&.strip,
      image_url: image_url
    }
  end
end
