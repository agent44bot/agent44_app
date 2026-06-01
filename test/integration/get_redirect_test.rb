require "test_helper"

# The QR smart-redirect at /get. Must route iOS -> App Store, everyone else ->
# website, and must NEVER 406 (it runs at the routing layer, before the app-wide
# allow_browser gate, so even the short iOS Camera/QR-preview UA gets through).
class GetRedirectTest < ActionDispatch::IntegrationTest
  APP_STORE = "https://apps.apple.com/app/id6762046812".freeze
  WEBSITE   = "https://agent44labs.ai".freeze

  def get_with_ua(ua)
    get "/get", headers: { "HTTP_USER_AGENT" => ua }
  end

  test "iPhone (full UA) redirects to the App Store" do
    get_with_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    assert_response :redirect
    assert_equal APP_STORE, response.location
  end

  test "iPhone Camera short UA still reaches the App Store (no 406)" do
    get_with_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
    assert_response :redirect
    assert_equal APP_STORE, response.location
  end

  test "iPad redirects to the App Store" do
    get_with_ua "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
    assert_equal APP_STORE, response.location
  end

  test "Android redirects to the website" do
    get_with_ua "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36"
    assert_response :redirect
    assert_equal WEBSITE, response.location
  end

  test "old Android (would fail allow_browser) still redirects, no 406" do
    get_with_ua "Mozilla/5.0 (Linux; Android 6.0) AppleWebKit/537.36"
    assert_response :redirect
    assert_equal WEBSITE, response.location
  end

  test "desktop redirects to the website" do
    get_with_ua "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36"
    assert_equal WEBSITE, response.location
  end

  test "redirect is 302 (not cached) so each scan re-evaluates the UA" do
    get_with_ua "Mozilla/5.0 (Linux; Android 14)"
    assert_equal 302, response.status
  end
end
