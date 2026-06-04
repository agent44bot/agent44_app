require "test_helper"

class CarsonNudgeJobTest < ActiveJob::TestCase
  setup do
    Setting.delete_all
    Notification.delete_all
    @rich = User.create!(email_address: "nudge-rich-#{SecureRandom.hex(4)}@example.com", role: "admin")
    Setting.set("carson_nudges:user_ids", @rich.id.to_s)
    # Flyer timestamp seeded fresh so only the trigger under test fires.
    Setting.touch_time("nyk_flyer_prints:last_at")
  end

  # Build a job whose dice roll always passes. APNs never reaches Apple in
  # tests: ApnsPusher.send_alert returns before connecting when the user has
  # no DeviceToken rows (always the case here).
  def run_job(force: false, at: Time.zone.parse("#{Date.current} 14:30"))
    job = CarsonNudgeJob.new
    def job.dice_roll = 0.0
    travel_to(at) { job.perform(force: force) }
  end

  def snapshot_with_event(spots_left: 10, name: "Pasta Night")
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    snap.kitchen_events.create!(url: "https://tock/x-#{SecureRandom.hex(2)}", name: name,
                                start_at: 3.days.from_now, spots_left: spots_left,
                                capacity: 12, availability: "available")
    snap
  end

  test "no recipients -> nothing happens" do
    Setting.set("carson_nudges:user_ids", "")
    snapshot_with_event(spots_left: 1)
    run_job
    assert_equal 0, Notification.count
  end

  test "almost-sold-out class sends a Carson push with an ask deep link" do
    snapshot_with_event(spots_left: 2, name: "Sweet Heat")
    run_job
    n = Notification.last
    assert n, "expected a notification"
    assert_equal "carson", n.source
    assert_equal @rich, n.user
    assert_match "Sweet Heat", n.title
    assert_match %r{^/nykitchen/ask\?q=}, n.url
    assert_equal 1, Setting.counter("carson_nudges:sent:#{Date.current.iso8601}")
  end

  test "respects the daily budget" do
    snapshot_with_event(spots_left: 1)
    Setting.set("carson_nudges:sent:#{Date.current.iso8601}", "2")
    run_job
    assert_equal 0, Notification.count
  end

  test "respects trigger cooldown" do
    snapshot_with_event(spots_left: 1)
    Setting.touch_time("carson_nudges:cooldown:almost_sold_out")
    run_job
    assert_equal 0, Notification.count
  end

  test "quiet outside the send window" do
    snapshot_with_event(spots_left: 1)
    run_job(at: Time.zone.parse("#{Date.current} 22:00"))
    assert_equal 0, Notification.count
  end

  test "force bypasses window and budget for manual prod testing" do
    snapshot_with_event(spots_left: 1)
    Setting.set("carson_nudges:sent:#{Date.current.iso8601}", "2")
    run_job(force: true, at: Time.zone.parse("#{Date.current} 22:00"))
    assert_equal 1, Notification.count
  end

  test "no flyers in a week nudges toward the print page" do
    Setting.set("nyk_flyer_prints:last_at", 8.days.ago.iso8601)
    run_job
    n = Notification.last
    assert n, "expected a notification"
    assert_equal "/nykitchen/display/print", n.url
  end

  test "first run seeds the flyer timestamp instead of nudging" do
    Setting.delete_key("nyk_flyer_prints:last_at")
    run_job
    assert_equal 0, Notification.count
    assert Setting.time("nyk_flyer_prints:last_at"), "should seed last_at"
  end

  test "slow sales day links to Iris" do
    # Today's snapshot with zero sales vs a healthy 14-day average.
    prev_events = nil
    (1..13).each do |i|
      snap = KitchenSnapshot.create!(taken_on: i.days.ago.to_date)
      snap.kitchen_events.create!(url: "https://tock/avg", name: "Avg Class",
                                  start_at: 30.days.from_now, capacity: 20,
                                  spots_left: 20 - (14 - i), availability: "available")
    end
    today = KitchenSnapshot.create!(taken_on: Date.current)
    today.kitchen_events.create!(url: "https://tock/avg", name: "Avg Class",
                                 start_at: 30.days.from_now, capacity: 20,
                                 spots_left: 7, availability: "available")
    run_job(at: Time.zone.parse("#{Date.current} 15:00"))
    n = Notification.last
    assert n, "expected a notification"
    assert_equal "/nykitchen/analyst", n.url
  end
end
