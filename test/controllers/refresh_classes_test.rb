require "test_helper"
require "minitest/mock"

# "Refresh classes" on the flyer/poster pages. The flyer prints the last
# snapshot, so a class pulled from nykitchen.com during the day kept printing
# until the nightly scrape (Dakota's cancelled Sunday pop-up). Managers can
# force a re-scrape; nobody else can, and not on a hair trigger.
class RefreshClassesTest < ActionDispatch::IntegrationTest
  setup do
    @owner   = User.create!(email_address: "nyk-refresh-owner-#{SecureRandom.hex(4)}@example.com", role: "user")
    @outsider = User.create!(email_address: "nyk-refresh-out-#{SecureRandom.hex(4)}@example.com", role: "user")
    @workspace = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
    Setting.delete_key("nyk_classes_refreshed_at")
  end

  # Scraping from the app server always comes back empty (SiteGround CAPTCHAs
  # Fly's IP), so the button asks the Mac mini runner to scrape instead.
  test "a manager asks the mini runner for a scrape" do
    sign_in_as(@owner)
    got = nil
    SmokeDispatch.stub(:trigger!, ->(**kw) { got = kw; :ok }) do
      post nyk_refresh_classes_path
    end

    assert_equal "scrape", got[:test]
    assert_equal "Refresh classes", got[:via]
    assert_redirected_to nyk_display_print_path
    assert_match(/Refreshing classes/, flash[:notice])
  end

  test "a failed trigger says so and does not start the cooldown" do
    sign_in_as(@owner)
    SmokeDispatch.stub(:trigger!, ->(**) { :failed }) do
      post nyk_refresh_classes_path
    end
    assert_match(/couldn.t start the refresh/i, flash[:alert])
    assert_nil Setting.time("nyk_classes_refreshed_at"), "a failed trigger must stay retryable"
  end

  test "a signed-in non-manager cannot" do
    sign_in_as(@outsider)
    triggered = false
    SmokeDispatch.stub(:trigger!, ->(**) { triggered = true; :ok }) do
      post nyk_refresh_classes_path
    end
    assert_not triggered
    assert_response :not_found
  end

  test "anonymous visitors cannot (the print page is public)" do
    triggered = false
    SmokeDispatch.stub(:trigger!, ->(**) { triggered = true; :ok }) do
      post nyk_refresh_classes_path
    end
    assert_not triggered
    assert_response :redirect # bounced to sign-in
  end

  test "a second click inside the cooldown is refused, not dispatched" do
    sign_in_as(@owner)
    calls = 0
    SmokeDispatch.stub(:trigger!, ->(**) { calls += 1; :ok }) do
      post nyk_refresh_classes_path
      post nyk_refresh_classes_path
    end
    assert_equal 1, calls, "the cooldown must stop a second dispatch"
    assert_match(/just refreshed/i, flash[:alert])
  end

  test "the button only shows on the flyer for managers" do
    KitchenSnapshot.create!(taken_on: Date.current).kitchen_events.create!(
      url: "https://nykitchen.com/event/x", name: "Knife Skills",
      start_at: 24.hours.from_now, availability: "InStock"
    )

    get nyk_display_print_path
    assert_select "form[action=?]", nyk_refresh_classes_path, 0, "hidden from anonymous walk-ups"

    sign_in_as(@owner)
    get nyk_display_print_path
    assert_select "form[action=?]", nyk_refresh_classes_path, 1
  end
end
