require "test_helper"

# The owner-only /admin/track page: anonymous (signed-out) traffic rollup row
# and the user_id=anonymous drill-in.
class AdminTrackAnonymousTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.find_or_create_by!(email_address: "botwhisperer@hey.com") { |u| u.role = "admin" }
    @owner.update!(role: "admin")
    sign_in_as(@owner)

    PageView.create!(path: "/nykitchen", session_id: "anon-sess-1", user_id: nil)
    PageView.create!(path: "/workspaces/nykitchen/drafts/34/edit", session_id: "anon-sess-2", user_id: nil)
    PageView.create!(path: "/jobs", session_id: "user-sess", user_id: @owner.id)
  end

  test "overview shows an Anonymous rollup row with hits and sessions" do
    get admin_track_path(range: "today")
    assert_response :success
    assert_match "Anonymous", response.body
    assert_match "signed-out visitors", response.body
  end

  test "anonymous drill-in lists only signed-out views with session prefixes" do
    get admin_track_path(user_id: "anonymous", range: "today")
    assert_response :success
    assert_match "Track anonymous visitors", response.body
    assert_match "/workspaces/nykitchen/drafts/34/edit", response.body
    assert_match "anon-ses", response.body
    assert_no_match "/jobs", response.body.split("Activity feed").last
  end

  test "non-owner cannot reach the track page" do
    other = User.create!(email_address: "other-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(other)
    get admin_track_path(user_id: "anonymous")
    assert_redirected_to root_path
  end
end
