require "test_helper"
require "minitest/mock"

class NyKitchenScraperTest < ActiveSupport::TestCase
  setup { @scraper = NyKitchenScraper.new }

  # Mirrors a real NY Kitchen detail page: a single JSON-LD block with the Event
  # (and its Offer) nested inside @graph.
  SOLD_OUT_JSONLD = <<~HTML.freeze
    <script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[
      {"@type":"Event","name":"Peaches","url":"https://nykitchen.com/event/peaches/",
       "offers":[{"@type":"Offer","availability":"SoldOut","price":"85"}]}
    ]}
    </script>
  HTML

  test "prefers the JSON-LD #primaryimage over a fallback og:image" do
    html = <<~HTML
      <html><head>
        <meta property="og:image" content="https://nykitchen.com/wp-content/uploads/GTP_NYK-OUTDOORS-7067.jpg" />
        <script type="application/ld+json">
        {"@graph":[
          {"@type":"WebPage","@id":"https://nykitchen.com/event/x/#webpage"},
          {"@type":"ImageObject","@id":"https://nykitchen.com/event/x/#primaryimage","url":"https://nykitchen.com/wp-content/uploads/wine.avif"}
        ]}
        </script>
      </head><body></body></html>
    HTML
    assert_equal "https://nykitchen.com/wp-content/uploads/wine.avif",
                 @scraper.extract_event_image(html)
  end

  test "falls back to og:image when the page has no primaryimage node" do
    html = <<~HTML
      <html><head>
        <meta property="og:image" content="https://nykitchen.com/wp-content/uploads/IMG_7378-1-scaled.jpg" />
        <script type="application/ld+json">{"@graph":[{"@type":"WebPage","@id":"x"}]}</script>
      </head><body></body></html>
    HTML
    assert_equal "https://nykitchen.com/wp-content/uploads/IMG_7378-1-scaled.jpg",
                 @scraper.extract_event_image(html)
  end

  test "primaryimage is found regardless of JSON field order" do
    html = <<~HTML
      <html><head>
        <meta property="og:image" content="https://nykitchen.com/wp-content/uploads/GTP_NYK-OUTDOORS-7067.jpg" />
        <script type="application/ld+json">
        {"@graph":[
          {"url":"https://nykitchen.com/wp-content/uploads/wine.avif","@type":"ImageObject","@id":"https://nykitchen.com/event/x/#primaryimage"}
        ]}
        </script>
      </head></html>
    HTML
    assert_equal "https://nykitchen.com/wp-content/uploads/wine.avif",
                 @scraper.extract_event_image(html)
  end

  test "extracts the menu from the nyk-event-meta-title section" do
    html = <<~HTML
      <div class="tribe-events-cost">&#036;85.00</div>
      <h3 class="nyk-event-meta-title">Menu</h3>
      <p>Strawberry Balsamic Crostini, Strawberry Basil Chicken</p>
      <p>Puff Pastry Strawberry Shortcake</p>
      <a href="#event-disclosures" class="button--disclosures">Event/Class Disclosures</a>
    HTML
    assert_equal "Strawberry Balsamic Crostini, Strawberry Basil Chicken / Puff Pastry Strawberry Shortcake",
                 @scraper.extract_event_menu(html)
  end

  test "menu is nil when the page has no Menu section" do
    assert_nil @scraper.extract_event_menu("<h3 class=\"nyk-event-meta-title\">Tasting Notes</h3><p>Dry</p>")
  end

  test "detail_json_ld_sold_out? reads SoldOut from the event offer nested in @graph" do
    assert @scraper.send(:detail_json_ld_sold_out?, SOLD_OUT_JSONLD)
    assert_not @scraper.send(:detail_json_ld_sold_out?, SOLD_OUT_JSONLD.sub("SoldOut", "InStock"))
  end

  test "fetch_availability reports sold out from JSON-LD when the ticket widget exposes no seat count" do
    # A sold-out NYK page drops its data-available-count attributes, so the
    # ticket-block parse finds nothing. The offer JSON-LD still says SoldOut.
    html = SOLD_OUT_JSONLD + <<~HTML
      <div class="tribe-tickets__tickets-item tribe-tickets__tickets-item--unavailable">
        <span class="tribe-tickets__tickets-item-quantity-unavailable">Sold Out</span>
      </div>
    HTML
    result = @scraper.stub(:get, html) do
      @scraper.fetch_availability("https://nykitchen.com/event/peaches/")
    end
    assert_equal 0, result[:spots_left]
    assert_nil result[:capacity]
  end

  test "fetch_availability returns nil for an open class with no parseable count and no sold-out signal" do
    html = '<html><body><div class="tribe-events-content"><p>Register below</p></div></body></html>'
    result = @scraper.stub(:get, html) do
      @scraper.fetch_availability("https://nykitchen.com/event/open/")
    end
    assert_nil result
  end

  # ---------------------------------------------------------------------------
  # Tribe Events REST API listing.
  #
  # The listing moved off JSON-LD scraping because SiteGround's CAPTCHA
  # intermittently served a challenge page instead of the calendar. None of this
  # path had coverage, so these pin the field mapping, the paging stop
  # conditions, and which HTTP codes count as success. No network: fetch_rest_api
  # and Net::HTTP are stubbed.
  # ---------------------------------------------------------------------------

  TRIBE_EVENT = {
    "url"         => "https://nykitchen.com/event/knife-skills/",
    "title"       => "Knife Skills",
    "start_date"  => "2026-08-10 18:00:00",
    "end_date"    => "2026-08-10 20:00:00",
    "cost"        => "&#36;85",
    "description" => "  Sharpen up.  ",
    "image"       => { "url" => "https://nykitchen.com/wp-content/uploads/knife.jpg" }
  }.freeze

  test "maps Tribe REST fields onto the normalized event shape" do
    event = @scraper.send(:normalize_tribe_event, TRIBE_EVENT)

    assert_equal "Knife Skills", event[:name]
    assert_equal "https://nykitchen.com/event/knife-skills/", event[:url]
    # The API sends naive local times. Reading them as UTC would shift every
    # class four hours earlier, so a 6pm class must stay 6pm Eastern.
    assert_equal Time.zone.parse("2026-08-10 18:00:00"), event[:start_at]
    assert_equal Time.zone.parse("2026-08-10 20:00:00"), event[:end_at]
    assert_equal 18, event[:start_at].in_time_zone("Eastern Time (US & Canada)").hour
    assert_equal "New York Kitchen", event[:venue]
    # image arrives as a nested hash, not a string, and cost carries HTML entities
    assert_equal "https://nykitchen.com/wp-content/uploads/knife.jpg", event[:image_url]
    assert_equal "85", event[:price]
    assert_equal "Sharpen up.", event[:description]
  end

  test "skips events missing a start date or title rather than importing junk" do
    assert_nil @scraper.send(:normalize_tribe_event, TRIBE_EVENT.except("start_date"))
    assert_nil @scraper.send(:normalize_tribe_event, TRIBE_EVENT.merge("title" => nil))
    assert_nil @scraper.send(:normalize_tribe_event, TRIBE_EVENT.merge("start_date" => "not a date"))
  end

  test "fetch_events normalizes and de-duplicates across pages" do
    duplicate = TRIBE_EVENT.merge("title" => "Knife Skills (dupe)")
    calls = []
    fake = lambda do |url|
      calls << url
      { "events" => [ TRIBE_EVENT, duplicate ] }
    end

    events = @scraper.stub(:fetch_rest_api, fake) do
      @scraper.fetch_events(months: [ "2026-08" ])
    end

    # Same url on both records, so the second collapses into the first.
    assert_equal 1, events.size
    assert_equal "Knife Skills", events.first[:name]
    # A short page ends the loop, so exactly one request per month.
    assert_equal 1, calls.size
    assert_includes calls.first, "start_date=2026-08-01"
    assert_includes calls.first, "end_date=2026-08-31"
  end

  test "fetch_events stops instead of looping when the relay returns nothing" do
    events = @scraper.stub(:fetch_rest_api, ->(_url) { nil }) do
      @scraper.fetch_events(months: [ "2026-08" ])
    end
    assert_empty events

    events = @scraper.stub(:fetch_rest_api, ->(_url) { { "events" => [] } }) do
      @scraper.fetch_events(months: [ "2026-08" ])
    end
    assert_empty events
  end

  # Fly's load balancer answers 202 for a request it accepted, which an
  # exact `== "200"` check rejected and read as a scrape failure.
  test "accepts any 2xx from the API, not just 200" do
    [ "200", "202" ].each do |code|
      data = with_stubbed_http(code, { "events" => [ TRIBE_EVENT ] }.to_json) do
        @scraper.send(:fetch_rest_api, NyKitchenScraper::REST_API)
      end
      assert_equal 1, data["events"].size, "expected HTTP #{code} to be treated as success"
    end
  end

  test "returns nil on a non-2xx or unparseable response" do
    assert_nil(with_stubbed_http("403", "<html>CAPTCHA</html>") do
      @scraper.send(:fetch_rest_api, NyKitchenScraper::REST_API)
    end)

    assert_nil(with_stubbed_http("200", "<html>not json</html>") do
      @scraper.send(:fetch_rest_api, NyKitchenScraper::REST_API)
    end)
  end

  test "presents a nykitchen Referer and Origin so the CAPTCHA lets us through" do
    headers = {}
    captured = Object.new
    captured.define_singleton_method(:request) do |req|
      req.each_header { |k, v| headers[k] = v }
      Struct.new(:code, :body).new("200", { "events" => [] }.to_json)
    end
    captured.define_singleton_method(:use_ssl=) { |_| }
    captured.define_singleton_method(:open_timeout=) { |_| }
    captured.define_singleton_method(:read_timeout=) { |_| }

    Net::HTTP.stub(:new, captured) do
      @scraper.send(:fetch_rest_api, NyKitchenScraper::REST_API)
    end

    assert_equal "https://nykitchen.com/calendar/", headers["referer"]
    assert_equal "https://nykitchen.com", headers["origin"]
  end

  private

  # Swaps in a Net::HTTP whose request returns the given code and body.
  def with_stubbed_http(code, body)
    http = Object.new
    http.define_singleton_method(:request) { |_req| Struct.new(:code, :body).new(code, body) }
    http.define_singleton_method(:use_ssl=) { |_| }
    http.define_singleton_method(:open_timeout=) { |_| }
    http.define_singleton_method(:read_timeout=) { |_| }
    Net::HTTP.stub(:new, http) { yield }
  end

  # ---------------------------------------------------------------------------
  # Follow-ups from the REST migration (PR #459 review), each verified against a
  # live API response before fixing.
  # ---------------------------------------------------------------------------

  test "decodes HTML entities in the title and description" do
    # Real strings from the live endpoint: 23 of 40 descriptions were encoded.
    raw = TRIBE_EVENT.merge(
      "title"       => "Chef&#8217;s Table Class 8/1/26",
      "description" => "Gnocchi &#38; Pasta"
    )
    event = @scraper.send(:normalize_tribe_event, raw)

    assert_equal "Chef’s Table Class 8/1/26", event[:name]
    assert_equal "Gnocchi & Pasta", event[:description]
    assert_not_includes event[:name], "&#"
    assert_not_includes event[:description], "&#"
  end

  test "pages by total_pages rather than inferring the end from a short page" do
    # The API can cap per_page below what we ask for. Inferring "done" from a
    # short page would stop after page 1 and silently drop the rest.
    pages = { 1 => [ TRIBE_EVENT ], 2 => [ TRIBE_EVENT.merge("url" => "https://nykitchen.com/event/second/") ] }
    seen_pages = []
    fake = lambda do |url|
      page = url[/[?&]page=(\d+)/, 1].to_i   # not per_page
      seen_pages << page
      { "events" => pages.fetch(page, []), "total_pages" => 2 }
    end

    events = @scraper.stub(:fetch_rest_api, fake) do
      @scraper.fetch_events(months: [ "2026-08" ])
    end

    assert_equal [ 1, 2 ], seen_pages
    assert_equal 2, events.size
  end

  test "still stops on a short page when the API omits total_pages" do
    calls = 0
    fake = lambda do |_url|
      calls += 1
      { "events" => [ TRIBE_EVENT ] }
    end
    @scraper.stub(:fetch_rest_api, fake) { @scraper.fetch_events(months: [ "2026-08" ]) }

    assert_equal 1, calls
  end

  test "reads the instructor off the detail page, since the listing has none" do
    html = <<~HTML
      <script type="application/ld+json">
      {"@graph":[{"@type":"Event","name":"Peaches",
        "performer":{"@type":"Person","name":"Chef Jos&#233;"}}]}
      </script>
    HTML

    assert_equal "Chef José", @scraper.extract_instructor(html)
    assert_nil @scraper.extract_instructor("<html>no json-ld</html>")
  end
end
