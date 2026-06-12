require "test_helper"

# The SSRF guard and URL validation in RecipeExtractor#fetch_url. We never let
# tests reach the network: only the rejection paths are exercised here, and the
# happy path is covered by the controller test via the class-level stub.
class RecipeExtractorUrlTest < ActiveSupport::TestCase
  def fetch(url)
    KitchenAi::RecipeExtractor.new.send(:fetch_url, url)
  end

  test "rejects non-http schemes" do
    r = fetch("ftp://example.com/recipe")
    assert_not r.ok?
    assert_match(/web address/, r.error)
  end

  test "rejects localhost and private hosts" do
    %w[http://localhost/x http://127.0.0.1/x http://10.0.0.5/x http://192.168.1.1/x].each do |u|
      r = fetch(u)
      assert_not r.ok?, "#{u} should be blocked"
      assert_match(/not allowed/, r.error)
    end
  end

  test "rejects junk that is not a URL" do
    assert_not fetch("not a url").ok?
  end

  # JSON-LD parsing (no network): the recipe card text is built from the
  # embedded schema, so ingredients reach the model even when the card sits far
  # down a long page.
  def parse_ld(html)
    KitchenAi::RecipeExtractor.new.send(:recipe_from_jsonld, html)
  end

  JSONLD = <<~HTML.freeze
    <html><head>
    <script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[
      {"@type":"WebPage","name":"ignore me"},
      {"@type":"Recipe","name":"Coq au Vin","recipeYield":"4 servings",
       "recipeIngredient":["1 whole chicken","2 cups red wine","8 oz mushrooms"],
       "recipeInstructions":[{"@type":"HowToStep","text":"Brown the chicken."},
                             {"@type":"HowToStep","text":"Add wine and simmer."}]}
    ]}
    </script></head><body>...lots of unrelated page text...</body></html>
  HTML

  test "extracts ingredients and steps from JSON-LD Recipe schema" do
    text = parse_ld(JSONLD)
    assert_includes text, "Coq au Vin"
    assert_includes text, "- 2 cups red wine"
    assert_includes text, "- 8 oz mushrooms"
    assert_includes text, "1. Brown the chicken."
  end

  test "returns nil when the page has no Recipe schema" do
    assert_nil parse_ld('<script type="application/ld+json">{"@type":"WebPage"}</script>')
    assert_nil parse_ld("<html><body>no json-ld here</body></html>")
  end

  test "ignores a Recipe node with no ingredients" do
    html = '<script type="application/ld+json">{"@type":"Recipe","name":"Empty"}</script>'
    assert_nil parse_ld(html)
  end
end
