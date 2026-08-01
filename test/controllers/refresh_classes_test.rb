require "test_helper"

# "Refresh classes" on the flyer/poster pages. The flyer prints the last
# snapshot, so a class pulled from nykitchen.com during the day kept printing
# until the nightly scrape (Dakota's cancelled Sunday pop-up). Managers can
# force a re-scrape; nobody else can, and not on a hair trigger.
class RefreshClassesTest < ActionDispatch::IntegrationTest
  setup do
    @owner   = User.create!(email_address: "nyk-refresh-owner-#{SecureRandom.hex(4)}@example.com", role: "user")
    @outsider = User.create!(email_address: "nyk-refresh-out-#{SecureRandom.hex(4)}@example.com", role: "user")
    @workspace = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
    @workspace.update!(owner: @owner)
    Setting.delete_key("nyk_classes_refreshed_at")
  end

  test "a manager queues a forced re-scrape" do
    sign_in_as(@owner)
    assert_enqueued_with(job: ScrapeKitchenJob, args: [ { force: true } ]) do
      post nyk_refresh_classes_path
    end
    assert_redirected_to nyk_display_print_path
    assert_match(/Refreshing classes/, flash[:notice])
  end

  test "a signed-in non-manager cannot" do
    sign_in_as(@outsider)
    assert_no_enqueued_jobs only: ScrapeKitchenJob do
      post nyk_refresh_classes_path
    end
    assert_response :not_found
  end

  test "anonymous visitors cannot (the print page is public)" do
    assert_no_enqueued_jobs only: ScrapeKitchenJob do
      post nyk_refresh_classes_path
    end
    assert_response :redirect # bounced to sign-in
  end

  test "a second click inside the cooldown is refused, not queued" do
    sign_in_as(@owner)
    post nyk_refresh_classes_path
    assert_no_enqueued_jobs only: ScrapeKitchenJob do
      post nyk_refresh_classes_path
    end
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
