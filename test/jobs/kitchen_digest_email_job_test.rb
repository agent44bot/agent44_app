require "test_helper"

class KitchenDigestEmailJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    snapshot = KitchenSnapshot.create!(taken_on: Date.current)
    snapshot.kitchen_events.create!(
      url: "https://nykitchen.com/e1", name: "Class A", start_at: 3.days.from_now,
      availability: "InStock", price: "100.00", capacity: 10, spots_left: 4
    )
  end

  # The footer line is rendered by the weekly report partial on every send, so
  # it's a reliable "is the Carson report present?" marker.
  WEEKLY_MARKER = "by your NY Kitchen agent team"

  test "non-Monday: one email with the class list and no weekly team report" do
    travel_to Time.zone.parse("2026-06-23 10:00") do # Tuesday
      assert_emails(1) { KitchenDigestEmailJob.perform_now }
      mail = ActionMailer::Base.deliveries.last
      assert_match "NY Kitchen", mail.subject
      assert_no_match WEEKLY_MARKER, mail.body.to_s
      assert_nil Setting.time("nyk_weekly_report:last_sent_at")
    end
  end

  test "Monday: the weekly team report is prepended into the same daily email" do
    travel_to Time.zone.parse("2026-06-22 10:00") do # Monday
      assert_emails(1) { KitchenDigestEmailJob.perform_now }
      mail = ActionMailer::Base.deliveries.last
      body = mail.body.to_s
      # Carson's report (its footer) AND the class list are in one email.
      assert_match WEEKLY_MARKER, body
      assert_match "Class A", body
      assert_not_nil Setting.time("nyk_weekly_report:last_sent_at"),
        "Monday send should stamp the weekly report engagement timestamp"
    end
  end
end
