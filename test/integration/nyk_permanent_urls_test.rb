require "test_helper"

# NY Kitchen's public URLs are permanent: they are on printed QR codes, the
# tasting-room display screen, staff bookmarks, and the iOS app's Universal
# Links (AASA lists /nykitchen/*). The multi-tenant refactor moves routing
# around; these literal paths (no route helpers, on purpose) must keep
# answering 200 no matter how the routes are mounted.
class NykPermanentUrlsTest < ActionDispatch::IntegrationTest
  setup do
    owner = User.create!(email_address: "nyk-owner-#{SecureRandom.hex(3)}@example.com", role: "admin")
    Workspace.create!(name: "NY Kitchen", slug: "nykitchen", owner: owner, kitchen_enabled: true)
  end

  test "GET /nykitchen/display/print is public and returns 200" do
    get "/nykitchen/display/print"
    assert_response :success
  end

  test "GET /nykitchen/display is public and returns 200" do
    get "/nykitchen/display"
    assert_response :success
  end

  test "GET /nykitchen (the hub) is public and returns 200" do
    get "/nykitchen"
    assert_response :success
  end
end
