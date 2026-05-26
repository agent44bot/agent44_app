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
end
