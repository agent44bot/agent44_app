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
end
