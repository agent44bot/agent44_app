require "test_helper"

# The print/display page is the one route where the query string is a distinct
# page worth its own analytics row: ?variant=stall (stall poster) vs the default
# flyer. Trackable records request.fullpath there so the two don't collapse to a
# single /nykitchen/display/print path. Every other route keeps bare path.
class TrackableQueryPathTest < ActionDispatch::IntegrationTest
  UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15".freeze

  test "stall variant is tracked as a distinct path on the print page" do
    perform_enqueued_jobs do
      get "/nykitchen/display/print?variant=stall", headers: { "User-Agent" => UA }
    end
    assert PageView.exists?(path: "/nykitchen/display/print?variant=stall"),
      "stall print visit should keep its query string"
    assert_not PageView.exists?(path: "/nykitchen/display/print"),
      "stall visit should not collapse onto the bare print path"
  end

  test "default flyer print visit records the bare path" do
    perform_enqueued_jobs do
      get "/nykitchen/display/print", headers: { "User-Agent" => UA }
    end
    assert PageView.exists?(path: "/nykitchen/display/print")
  end

  test "query strings on other routes are not tracked" do
    perform_enqueued_jobs do
      get "/?ref=newsletter", headers: { "User-Agent" => UA }
    end
    pv = PageView.order(created_at: :desc).first
    assert_equal "/", pv.path, "non-print routes should record bare path, not fullpath"
  end
end
