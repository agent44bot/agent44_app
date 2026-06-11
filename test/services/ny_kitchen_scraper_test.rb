require "test_helper"

class NyKitchenScraperTest < ActiveSupport::TestCase
  setup { @scraper = NyKitchenScraper.new }

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
end
