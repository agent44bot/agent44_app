require "test_helper"
require "minitest/mock"

class NykQrHealthCheckJobTest < ActiveSupport::TestCase
  setup do
    owner = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = owner }
    @snap = KitchenSnapshot.create!(taken_on: Date.current)
    Setting.delete_key(NykQrHealthCheckJob::FAILED_AT)
    Setting.delete_key(NykQrHealthCheckJob::MESSAGE)
  end

  # Adds an upcoming class + its tracked link (the thing the job checks).
  def add_class(url)
    @snap.kitchen_events.create!(url: url, name: "Class #{SecureRandom.hex(2)}",
                                 start_at: 2.days.from_now, availability: "InStock")
    TrackedLink.for_url(url, workspace: @ws)
  end

  # Runs the job with Notification.notify! stubbed so no real push/telegram
  # fires; returns the list of notify! calls.
  def run_job
    notified = []
    Notification.stub(:notify!, ->(*_a, **kw) { notified << kw; nil }) do
      NykQrHealthCheckJob.new.perform
    end
    notified
  end

  test "healthy chain: no flag, no alert" do
    add_class("https://nykitchen.com/event/wine-101/")
    add_class("https://www.exploretock.com/nykitchen/experience/pasta")
    notified = run_job
    assert_nil Setting.time(NykQrHealthCheckJob::FAILED_AT)
    assert_empty notified
  end

  test "a tracked link off nykitchen.com trips the alarm and pushes once" do
    add_class("https://nykitchen.com/event/ok/")
    add_class("https://agent44labs.com/nykitchen/r/loop") # would loop back to us
    notified = run_job
    assert Setting.time(NykQrHealthCheckJob::FAILED_AT), "should set the failed flag"
    assert_match "nykitchen.com ticket page", Setting.get(NykQrHealthCheckJob::MESSAGE)
    assert_equal 1, notified.size
    assert_equal "error", notified.first[:level]
    assert_equal true, notified.first[:apns]
  end

  test "does not re-push while already failing" do
    add_class("https://agent44labs.com/oops")
    assert_equal 1, run_job.size          # first failure pushes
    assert_empty run_job                  # still failing, no second push
    assert Setting.time(NykQrHealthCheckJob::FAILED_AT)
  end

  test "recovers: clears the flag and sends a recovery push" do
    Setting.touch_time(NykQrHealthCheckJob::FAILED_AT)
    Setting.set(NykQrHealthCheckJob::MESSAGE, "was broken")
    add_class("https://nykitchen.com/event/fine/")
    notified = run_job
    assert_nil Setting.time(NykQrHealthCheckJob::FAILED_AT)
    assert_equal 1, notified.size
    assert_equal "success", notified.first[:level]
  end

  test "in-app referrer heuristic trips when recent scans are mostly in-app" do
    link = add_class("https://nykitchen.com/event/ref/")
    9.times { link.link_scans.create!(scanned_at: 1.hour.ago, user_agent: "iPhone", referrer: "https://agent44labs.com/") }
    run_job
    assert Setting.time(NykQrHealthCheckJob::FAILED_AT)
    assert_match "in-app referrer", Setting.get(NykQrHealthCheckJob::MESSAGE)
  end

  test "a few in-app referrers below the volume floor do not trip it" do
    link = add_class("https://nykitchen.com/event/ref2/")
    3.times { link.link_scans.create!(scanned_at: 1.hour.ago, user_agent: "iPhone", referrer: "https://agent44labs.com/") }
    run_job
    assert_nil Setting.time(NykQrHealthCheckJob::FAILED_AT)
  end
end
