require "test_helper"
require "minitest/mock"

# Both public NY Kitchen endpoints are billed per hit, so automated traffic has
# to be kept out of the counters. On 2026-08-01 a link-safety crawler followed
# every QR on the flyer minutes after the URL went out by email: 30 "scans" from
# 21 datacenter IPs, all desktop, all invoiced at 4c.
class FlyerBotTrafficTest < ActionDispatch::IntegrationTest
  PHONE   = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148".freeze
  # What the crawler fleet actually sent: an ordinary desktop Chrome string.
  CRAWLER = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36".freeze
  PREVIEW = "Mozilla/5.0 (Windows NT 6.1; WOW64) SkypeUriPreview Preview/0.5".freeze

  setup do
    @owner = User.create!(email_address: "bt-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
    @snap = KitchenSnapshot.create!(taken_on: Date.current)
    @event = @snap.kitchen_events.create!(url: "https://nykitchen.com/event/x/", name: "Class X",
                                          start_at: 2.days.from_now, availability: "InStock")
    @link = TrackedLink.for_url(@event.url, workspace: @ws)
  end

  # --- scans -------------------------------------------------------------

  test "a phone camera scan is counted and billed" do
    assert_difference -> { @link.link_scans.count }, 1 do
      assert_difference -> { UsageEvent.of_kind(UsageEvent::FLYER_SCAN).count }, 1 do
        get nyk_scan_path(@link.token), headers: { "User-Agent" => PHONE }
      end
    end
  end

  test "a desktop crawler wearing a stock Chrome string is neither counted nor billed" do
    assert_no_difference -> { LinkScan.count } do
      assert_no_difference -> { UsageEvent.count } do
        get nyk_scan_path(@link.token), headers: { "User-Agent" => CRAWLER }
      end
    end
  end

  test "a link previewer is neither counted nor billed" do
    assert_no_difference -> { LinkScan.count } do
      get nyk_scan_path(@link.token), headers: { "User-Agent" => PREVIEW }
    end
  end

  test "an uncounted visitor still reaches the class page" do
    get nyk_scan_path(@link.token), headers: { "User-Agent" => CRAWLER }
    assert_redirected_to @event.url
    assert_equal 302, response.status
  end

  # --- prints ------------------------------------------------------------

  test "a browser beacon is counted and billed" do
    assert_difference -> { UsageEvent.of_kind(UsageEvent::FLYER_PRINT).count }, 1 do
      post nyk_record_print_path, headers: { "User-Agent" => CRAWLER }
    end
  end

  test "a scripted or headless beacon is not" do
    [ "curl/8.7.1", "python-requests/2.32", "Mozilla/5.0 HeadlessChrome/149.0.0.0", PREVIEW, "" ].each do |ua|
      assert_no_difference -> { UsageEvent.count }, "#{ua.inspect} should not bill" do
        post nyk_record_print_path, headers: { "User-Agent" => ua }
      end
    end
  end

  test "the beacon records the variant it was sent" do
    post nyk_record_print_path(variant: "stall"), headers: { "User-Agent" => CRAWLER }
    assert_equal "stall", UsageEvent.of_kind(UsageEvent::FLYER_PRINT).order(:id).last.metadata["variant"]
  end

  test "repeat opens from one visitor collapse into a single billable print" do
    # The dedupe window leans on Rails.cache, which is :null_store in test.
    Rails.cache.stub(:write, ->(*, **) { false }) do
      assert_no_difference -> { UsageEvent.count } do
        post nyk_record_print_path, headers: { "User-Agent" => CRAWLER }
      end
    end
  end
end
