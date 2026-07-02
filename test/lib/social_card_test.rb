require "test_helper"

# SocialCard parses OG/Twitter card metadata from a page. The HTTP fetch is
# stubbed so nothing leaves the process; we assert the parse + graceful nils.
class SocialCardTest < ActiveSupport::TestCase
  teardown { SocialCard.stub = nil }

  HTML = <<~HTML.freeze
    <html><head>
      <title>Fallback Title</title>
      <meta property="og:title" content="Creating The Perfect Curry Class" />
      <meta property="og:description" content="Learn to make delicious Indian food at home." />
      <meta property="og:image" content="https://nykitchen.com/wp-content/uploads/curry.jpg" />
      <meta name="twitter:card" content="summary_large_image" />
    </head><body>...</body></html>
  HTML

  test "parses og:title, description, and image" do
    card = SocialCard.parse(HTML, "https://nykitchen.com/event/curry/")
    assert_equal "Creating The Perfect Curry Class", card.title
    assert_equal "Learn to make delicious Indian food at home.", card.description
    assert_equal "https://nykitchen.com/wp-content/uploads/curry.jpg", card.image_url
    assert_equal "https://nykitchen.com/event/curry/", card.url
  end

  test "falls back to twitter tags then the <title> element" do
    html = "<html><head><title>Just A Title</title>" \
           '<meta name="twitter:title" content="Tw Title"></head></html>'
    card = SocialCard.parse(html, "https://x.test/p")
    assert_equal "Tw Title", card.title
    assert_nil card.image_url
  end

  test "resolves a relative og:image against the page URL" do
    html = '<meta property="og:title" content="T"><meta property="og:image" content="/img/a.jpg">'
    card = SocialCard.parse(html, "https://nykitchen.com/event/x/")
    assert_equal "https://nykitchen.com/img/a.jpg", card.image_url
  end

  test "unescapes HTML entities in metadata" do
    html = '<meta property="og:title" content="Chef&#39;s Table &amp; Wine">'
    card = SocialCard.parse(html, "https://x.test/p")
    assert_equal "Chef's Table & Wine", card.title
  end

  test "returns nil when there is no usable title" do
    assert_nil SocialCard.parse("<html><body>no head</body></html>", "https://x.test/p")
  end

  test "returns nil on a blank url" do
    assert_nil SocialCard.fetch("")
  end

  test "the class-level stub short-circuits the fetch" do
    SocialCard.stub = ->(url) { SocialCard::Card.new(url: url, title: "Stubbed") }
    assert_equal "Stubbed", SocialCard.fetch("https://anything").title
  end
end
