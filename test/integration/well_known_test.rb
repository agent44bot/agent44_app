require "test_helper"

class WellKnownTest < ActionDispatch::IntegrationTest
  test "serves the AASA as JSON, no auth required" do
    get "/.well-known/apple-app-site-association"
    assert_response :success
    assert_equal "application/json", response.media_type

    body = JSON.parse(response.body)
    app_id = "MKN95GAN66.com.agent44labs.app"
    assert_equal [app_id], body.dig("webcredentials", "apps")
    assert_equal [app_id], body.dig("applinks", "details", 0, "appIDs")
    assert_includes body.dig("applinks", "details", 0, "components", 0).values, "/sign_in/link*"
  end
end
