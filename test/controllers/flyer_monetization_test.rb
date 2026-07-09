require "test_helper"

# Monetization: 44 cents per flyer print-page open and per QR scan, recorded as
# UsageEvents and surfaced (owner/admin only) on the Neon card + billing page.
class FlyerMonetizationTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
    @snap = KitchenSnapshot.create!(taken_on: Date.current)
    @event = @snap.kitchen_events.create!(url: "https://nykitchen.com/event/x/", name: "Class X",
                                          start_at: 2.days.from_now, availability: "InStock")
  end

  test "opening the print page records a 44-cent flyer.print usage event" do
    assert_difference -> { UsageEvent.of_kind(UsageEvent::FLYER_PRINT).count }, 1 do
      get nyk_display_print_path
    end
    ue = UsageEvent.of_kind(UsageEvent::FLYER_PRINT).order(:id).last
    assert_equal 44, ue.unit_cents
    assert_equal @ws, ue.workspace
    assert_equal 44, ue.cost_cents
  end

  test "a scan records a 44-cent flyer.scan usage event" do
    link = TrackedLink.for_url(@event.url, workspace: @ws)
    assert_difference -> { UsageEvent.of_kind(UsageEvent::FLYER_SCAN).count }, 1 do
      get nyk_scan_path(link.token)
    end
    ue = UsageEvent.of_kind(UsageEvent::FLYER_SCAN).order(:id).last
    assert_equal 44, ue.unit_cents
    assert_equal @ws, ue.workspace
  end

  test "an unknown token does not bill a scan" do
    assert_no_difference -> { UsageEvent.count } do
      get nyk_scan_path("deadbeef0000")
    end
  end

  test "flyer_revenue_dollars sums prints + scans at 44 cents" do
    3.times { UsageEvent.record!(workspace: @ws, kind: UsageEvent::FLYER_PRINT, unit_cents: 44) }
    5.times { UsageEvent.record!(workspace: @ws, kind: UsageEvent::FLYER_SCAN, unit_cents: 44) }
    assert_in_delta 3.52, UsageEvent.flyer_revenue_dollars(@ws, 1.day.ago..Time.current), 0.001
  end

  test "Neon card shows revenue to a manager but not to a plain member" do
    UsageEvent.record!(workspace: @ws, kind: UsageEvent::FLYER_SCAN, unit_cents: 44)

    admin = User.create!(email_address: "adm-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(admin)
    get "/nykitchen"
    assert_response :success
    assert_match(/\$0\.44 this month/, response.body)

    viewer = User.create!(email_address: "view-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws.memberships.create!(user: viewer, role: "viewer")
    sign_in_as(viewer)
    get "/nykitchen"
    assert_response :success
    assert_no_match(/this month.*\$/, response.body[/💰.*/].to_s)
    assert_no_match "💰", response.body
  end

  test "billing page lists flyer prints and scans with amounts" do
    2.times { UsageEvent.record!(workspace: @ws, kind: UsageEvent::FLYER_PRINT, unit_cents: 44) }
    4.times { UsageEvent.record!(workspace: @ws, kind: UsageEvent::FLYER_SCAN, unit_cents: 44) }

    sign_in_as(User.create!(email_address: "adm-#{SecureRandom.hex(4)}@example.com", role: "admin"))
    get nyk_billing_path
    assert_response :success
    assert_match "Flyer prints", response.body
    assert_match "QR scans", response.body
    assert_match "$2.64", response.body # 6 actions x $0.44
  end
end
