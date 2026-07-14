require "test_helper"

# The navbar build-progress bar polls /nykitchen/packets/active_builds every ~9s
# on every page for as long as a tab is open. Counting that background XHR as a
# page view inflates engagement (an idle open tab looks identically "active" to
# someone working), so Trackable::POLL_PATHS excludes it. A real, user-initiated
# page load on the same prefix must still be tracked.
class TrackablePollPathTest < ActionDispatch::IntegrationTest
  UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15".freeze

  setup { sign_in_as(users(:one)) }

  test "the build-bar poll endpoint is not tracked" do
    assert_no_difference -> { PageView.count } do
      perform_enqueued_jobs do
        get "/nykitchen/packets/active_builds", headers: { "User-Agent" => UA }
      end
    end
  end

  test "the always-on Neon display page is not tracked" do
    assert_no_difference -> { PageView.count } do
      perform_enqueued_jobs do
        get "/nykitchen/display", headers: { "User-Agent" => UA }
      end
    end
  end

  test "the display heartbeat ping is not tracked" do
    assert_no_difference -> { PageView.count } do
      perform_enqueued_jobs do
        post "/nykitchen/display/heartbeat", headers: { "User-Agent" => UA }
      end
    end
  end

  test "a real page load on the same prefix is still tracked" do
    perform_enqueued_jobs do
      get "/nykitchen", headers: { "User-Agent" => UA }
    end
    assert PageView.exists?(path: "/nykitchen"),
      "a genuine /nykitchen visit should still be recorded"
  end
end
