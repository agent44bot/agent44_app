require "test_helper"

# QR codes on the printed flyers encode a trackable redirect (/nykitchen/r/:token)
# instead of the raw class URL, so we can count scans. See TrackedLink / LinkScan.
class QrScanTrackingTest < ActionDispatch::IntegrationTest
  setup do
    @snapshot = KitchenSnapshot.create!(taken_on: Date.current)
    @event = @snapshot.kitchen_events.create!(
      url: "https://nykitchen.com/event/pinot-noir-decoded",
      name: "Pinot Noir Decoded",
      start_at: 24.hours.from_now,
      availability: "InStock"
    )
  end

  test "token is deterministic and short for a given url" do
    a = TrackedLink.token_for(@event.url)
    b = TrackedLink.token_for(@event.url)
    assert_equal a, b
    assert_equal 12, a.length
    refute_equal a, TrackedLink.token_for("https://nykitchen.com/event/other")
  end

  test "rendering the flyer registers a tracked link for each class" do
    # The QR is an SVG (the encoded URL isn't literal text), so we assert the
    # side effect: nyk_scan_qr creates the TrackedLink the QR points at.
    refute TrackedLink.exists?(url: @event.url)
    get nyk_display_print_path
    assert_response :success
    link = TrackedLink.find_by(url: @event.url)
    assert link, "flyer render should register a TrackedLink for the class"
    assert_equal TrackedLink.token_for(@event.url), link.token
  end

  test "scanning logs a scan with device and referrer, then 302s to the class" do
    link = TrackedLink.for_url(@event.url)
    assert_difference -> { link.link_scans.count }, 1 do
      get nyk_scan_path(link.token),
          headers: { "User-Agent" => "Mozilla/5.0 (iPhone)", "Referer" => "https://x.test/" }
    end
    assert_redirected_to @event.url
    assert_equal 302, response.status
    scan = link.link_scans.order(:id).last
    assert_equal "iPhone", LinkScan.device_bucket(scan.user_agent)
    assert_equal "https://x.test/", scan.referrer
  end

  test "an unknown token falls back to the calendar without 404ing a walk-in" do
    assert_no_difference -> { LinkScan.count } do
      get nyk_scan_path("deadbeef0000")
    end
    assert_redirected_to "https://nykitchen.com/calendar/"
  end

  test "the redirect is reachable without authentication" do
    link = TrackedLink.for_url(@event.url)
    get nyk_scan_path(link.token)
    assert_response :redirect # not bounced to a login wall
  end
end
