require "test_helper"

# Regression: the class list groups events into weeks off the *app's* zone
# (Eastern), not the server's UTC date. On the UTC-hosted prod box, Date.today
# rolls to tomorrow at 8pm ET; before the fix, a Sunday-evening class fell
# before this week's Monday bucket and disappeared from Sam's list until
# midnight ET. Pin the clock to that boundary and prove the class still renders.
class KitchenListTzTest < ActionDispatch::IntegrationTest
  test "an event happening tonight stays on the list at the UTC/Eastern boundary" do
    # 00:33 UTC on Mon 7/13 == 20:33 ET on Sun 7/12. Date.today (UTC) = 7/13,
    # Date.current (ET) = 7/12. The class is tonight, Sun 7/12 ET.
    travel_to Time.utc(2026, 7, 13, 0, 33, 0) do
      snap = KitchenSnapshot.create!(taken_on: Date.current)
      user = User.create!(email_address: "tz-#{SecureRandom.hex(4)}@example.com", role: "admin")
      sign_in_as(user)
      snap.kitchen_events.create!(
        url: "https://nykitchen.com/e/tonight-#{SecureRandom.hex(3)}",
        name: "Sunday Supper Class", start_at: 1.hour.from_now, end_at: 3.hours.from_now,
        availability: "InStock", price: 95, capacity: 20, spots_left: 8, venue: "NY Kitchen"
      )

      get nyk_list_path
      assert_response :success
      assert_select "[data-search-text*='sunday supper']", { minimum: 1 },
                    "tonight's class must appear in the current-week bucket, not fall off before it"
    end
  end
end
