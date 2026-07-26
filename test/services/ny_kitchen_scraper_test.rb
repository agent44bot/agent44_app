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
end
