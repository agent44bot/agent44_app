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

  test "anonymous bot noise on / and /sign_in is hidden from the drill-in" do
    PageView.create!(path: "/", session_id: "bot-sess-1", user_id: nil)
    PageView.create!(path: "/sign_in", session_id: "bot-sess-2", user_id: nil)

    get admin_track_path(user_id: "anonymous", range: "today")
    assert_response :success
    assert_no_match "bot-sess", response.body
    # Only the 2 real anonymous sessions from setup; the noise hits don't count.
    assert_match "2 distinct sessions", response.body
  end

  test "signed-in visits to / and /sign_in are still tracked" do
    PageView.create!(path: "/sign_in", session_id: "user-sess", user_id: @owner.id)
    get admin_track_path(user_id: @owner.id, range: "today")
    assert_response :success
    assert_match "/sign_in", response.body.split("Activity feed").last
  end

  test "chip is dimmed for a user with no activity in the selected range" do
    stale = User.create!(email_address: "stale-#{SecureRandom.hex(4)}@example.com", role: "user")
    PageView.create!(path: "/jobs", session_id: "old-sess", user_id: stale.id, created_at: 10.days.ago)

    get admin_track_path(range: "today")
    assert_response :success
    assert_match "No activity in selected range", response.body

    get admin_track_path(range: "30d")
    assert_response :success
    assert_no_match "No activity in selected range", response.body
  end

  test "non-owner cannot reach the track page" do
    other = User.create!(email_address: "other-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(other)
    get admin_track_path(user_id: "anonymous")
    assert_redirected_to root_path
  end
end
