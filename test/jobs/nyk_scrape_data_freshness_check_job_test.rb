require "test_helper"
require "minitest/mock"

class NykScrapeDataFreshnessCheckJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    Setting.delete_all
    KitchenSnapshot.destroy_all
    owner = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = owner }
  end

  # Build a snapshot with one event whose created_at is `age` in the past
  # (default: fresh). Returns the snapshot.
  def snapshot_with_event(taken_on: Date.current, age: 1.hour)
    snap = KitchenSnapshot.create!(taken_on: taken_on)
    ev = snap.kitchen_events.create!(url: "https://nykitchen.com/e/#{SecureRandom.hex(3)}",
                                     name: "Class", start_at: 2.days.from_now, availability: "InStock")
    ev.update_column(:created_at, age.ago)
    snap
  end

  # Runs the job with Notification.notify! stubbed so no real push/telegram
  # fires; returns the captured notify! keyword args.
  def run_job
    notified = []
    Notification.stub(:notify!, ->(*_a, **kw) { notified << kw; nil }) do
      NykScrapeDataFreshnessCheckJob.new.perform
    end
    notified
  end

  test "no alert when data is fresh" do
    snapshot_with_event(age: 1.hour)
    assert_empty run_job
    assert_nil Setting.time(NykScrapeDataFreshnessCheckJob::STATE_KEY)
  end

  test "alerts when the latest snapshot is empty" do
    KitchenSnapshot.create!(taken_on: Date.current) # zero events
    notified = run_job
    assert notified.any?, "expected an alert"
    assert notified.any? { |n| n[:telegram] }, "expected a Telegram alert"
    assert notified.any? { |n| n[:apns] }, "expected an iOS push"
    assert_equal "nyk_scrape", notified.first[:source]
    assert_equal "error", notified.first[:level]
    assert Setting.time(NykScrapeDataFreshnessCheckJob::STATE_KEY), "should stamp the cooldown"
  end

  test "alerts when no fresh scrape has landed in over 7 hours" do
    snapshot_with_event(age: 8.hours)
    notified = run_job
    assert notified.any?, "expected a staleness alert"
    assert notified.any? { |n| n[:apns] }
  end

  test "alerts when there are no snapshots at all" do
    assert run_job.any?, "expected an alert when the scrape has never posted"
  end

  test "respects the re-alert cooldown" do
    snapshot_with_event(age: 8.hours)
    Setting.set(NykScrapeDataFreshnessCheckJob::STATE_KEY, 1.hour.ago.iso8601)
    assert_empty run_job
  end

  test "re-alerts after the cooldown elapses" do
    snapshot_with_event(age: 8.hours)
    Setting.set(NykScrapeDataFreshnessCheckJob::STATE_KEY, 13.hours.ago.iso8601)
    assert run_job.any?
  end

  test "emails the NY Kitchen owners when broken" do
    snapshot_with_event(age: 8.hours)
    assert_enqueued_emails 1 do
      NykScrapeDataFreshnessCheckJob.new.perform
    end
  end

  test "does not email when data is fresh" do
    snapshot_with_event(age: 1.hour)
    assert_no_enqueued_emails do
      NykScrapeDataFreshnessCheckJob.new.perform
    end
  end
end
