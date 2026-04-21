require "net/http"
require "nokogiri"
require "json"
require "cgi"

class NyKitchenScraper
  BASE = "https://nykitchen.com/calendar/list/"
  UA   = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

  # Fetch events covering the given month range (YYYY-MM strings).
  # Paginates through The Events Calendar list view.
  def fetch_events(months:)
    seen = {}
    months.each do |ym|
      page = 1
      loop do
        url  = "#{BASE}?tribe-bar-date=#{ym}&tribe_paged=#{page}"
        html = get(url)
        break if html.nil?

        events = extract_jsonld_events(html)
        break if events.empty?

        new_count = 0
        events.each do |e|
          key = e["url"] || "#{e['name']}|#{e['startDate']}"
          unless seen.key?(key)
            seen[key] = e
            new_count += 1
          end
        end

        break if new_count.zero?
        page += 1
        break if page > 10
      end
    end
    seen.values.filter_map { |raw| normalize(raw) }
  end

  # Scrape an event detail page for live ticket availability.
  # Returns { spots_left:, capacity:, closed: } or nil.
  def fetch_availability(url)
    return nil if url.nil? || url.empty?
    html = get(url)
    return nil unless html

    if html.include?("Tickets are no longer available")
      return { spots_left: 0, capacity: nil, closed: true }
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

    { spots_left: spots_left, capacity: cap_known ? capacity : nil }
  end

  private

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
    unless response.code == "200"
      Rails.logger.warn("NyKitchenScraper: #{url} -> HTTP #{response.code}")
      return nil
    end

    body = response.body.force_encoding("UTF-8").scrub
    Rails.logger.info("NyKitchenScraper: #{url} #{body.bytesize}B jsonld=#{body.scan('application/ld+json').size}")
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

  def normalize(raw)
    start = raw["startDate"] && (DateTime.parse(raw["startDate"]) rescue nil)
    return nil unless start

    offers   = Array(raw["offers"]).first || {}
    location = raw["location"]
    location = location.first if location.is_a?(Array)
    venue    = location.is_a?(Hash) ? location["name"] : nil
    perf     = Array(raw["performer"]).first
    instructor = perf.is_a?(Hash) ? perf["name"] : nil
    decode = ->(s) { s ? CGI.unescapeHTML(s.to_s) : nil }

    {
      url:          raw["url"] || offers["url"],
      name:         decode.call(raw["name"]),
      start_at:     start.to_time,
      end_at:       (DateTime.parse(raw["endDate"]).to_time rescue nil),
      price:        offers["price"]&.to_s,
      availability: (offers["availability"] || "").to_s.sub("https://schema.org/", "").sub("http://schema.org/", ""),
      venue:        decode.call(venue),
      instructor:   decode.call(instructor),
      description:  decode.call(raw["description"])
    }
  end
end
