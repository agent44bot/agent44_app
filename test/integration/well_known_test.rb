require "test_helper"

class WellKnownTest < ActionDispatch::IntegrationTest
  test "serves the AASA as JSON, no auth required" do
    get "/.well-known/apple-app-site-association"
    assert_response :success
    assert_equal "application/json", response.media_type

    body = JSON.parse(response.body)
    app_id = "MKN95GAN66.com.agent44labs.app"
    assert_equal [ app_id ], body.dig("webcredentials", "apps")
    details = body.dig("applinks", "details")
    # Legacy (appID/paths) + modern (appIDs/components) entries, both for /sign_in/*.
    legacy = details.find { |d| d["appID"] }
    modern = details.find { |d| d["appIDs"] }
    assert_equal [ app_id ], modern["appIDs"]
    assert_includes legacy["paths"], "/sign_in/*"
    assert_includes modern["components"].first.values, "/sign_in/*"

    # In-app deep links (the report's "Open the ..." buttons) must open the app.
    assert_includes legacy["paths"], "/nykitchen/*"
    assert_includes modern["components"].flat_map(&:values), "/nykitchen/*"
  end
end
