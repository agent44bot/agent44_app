require "test_helper"

class Bluesky::FacetsTest < ActiveSupport::TestCase
  test "no facets for plain text" do
    assert_empty Bluesky::Facets.build("Hello world, nothing to see here.")
  end

  test "single URL becomes a link facet with correct byte offsets" do
    text = "Visit https://nykitchen.com/x soon."
    facets = Bluesky::Facets.build(text)
    link = facets.find { |f| f[:features].first["$type"] == "app.bsky.richtext.facet#link" }
    assert link, "expected a link facet"
    assert_equal "https://nykitchen.com/x", link[:features].first[:uri]
    # "Visit " = 6 bytes, URL is 23 chars all ASCII
    assert_equal 6,      link[:index][:byteStart]
    assert_equal 6 + 23, link[:index][:byteEnd]
  end

  test "trailing sentence punctuation gets stripped from the link" do
    text = "see https://example.com."
    link = Bluesky::Facets.build(text).first
    assert_equal "https://example.com", link[:features].first[:uri]
  end

  test "single hashtag becomes a tag facet (tag value strips the #)" do
    text = "Cooking class today #NYKitchen woo"
    facets = Bluesky::Facets.build(text)
    tag = facets.find { |f| f[:features].first["$type"] == "app.bsky.richtext.facet#tag" }
    assert tag
    assert_equal "NYKitchen", tag[:features].first[:tag]
    # "Cooking class today " = 20 bytes, "#NYKitchen" = 10
    assert_equal 20,      tag[:index][:byteStart]
    assert_equal 20 + 10, tag[:index][:byteEnd]
  end

  test "multiple hashtags + a link in one post" do
    text = "Class details: https://nykitchen.com/abc #NYKitchen #ROC"
    facets = Bluesky::Facets.build(text)
    assert_equal 3, facets.size
    types = facets.map { |f| f[:features].first["$type"] }.sort
    assert_equal [ "app.bsky.richtext.facet#link", "app.bsky.richtext.facet#tag", "app.bsky.richtext.facet#tag" ], types
  end

  test "byte offsets are correct when emoji precedes a URL (UTF-8 multibyte)" do
    # 🍳 is 4 bytes in UTF-8
    text  = "🍳 https://nykitchen.com/x"
    link  = Bluesky::Facets.build(text).first
    # "🍳 " = 5 bytes; URL starts at byte 5
    assert_equal 5,                       link[:index][:byteStart]
    assert_equal 5 + "https://nykitchen.com/x".bytesize, link[:index][:byteEnd]
  end

  test "doesn't hashtag-link mid-word (#hashtag inside email-like strings)" do
    text = "ping foo&#NYKitchen for details"
    facets = Bluesky::Facets.build(text)
    assert_empty facets.select { |f| f[:features].first["$type"] == "app.bsky.richtext.facet#tag" }
  end

  test "empty text returns empty facets without raising" do
    assert_equal [], Bluesky::Facets.build("")
    assert_equal [], Bluesky::Facets.build(nil)
  end
end
