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

  test "recipients are the opted-in NY Kitchen members; opt-outs excluded" do
    owner = User.create!(email_address: "owner@example.com")
    ws = Workspace.create!(name: "NY Kitchen", slug: "nykitchen",
                           owner_id: owner.id, timezone: "Eastern Time (US & Canada)")
    kept    = User.create!(email_address: "kept@example.com")
    dropped = User.create!(email_address: "dropped@example.com")
    ws.memberships.create!(user: kept,    role: "editor")                               # default on
    ws.memberships.create!(user: dropped, role: "editor", daily_digest_enabled: false)  # opted out

    recips = KitchenDigestEmailJob.recipients
    assert_includes recips, "owner@example.com",   "owner (default on) included"
    assert_includes recips, "kept@example.com",    "opted-in member included"
    assert_not_includes recips, "dropped@example.com", "opted-out member excluded"
  end

  test "recipients fall back to the core list when the workspace is missing" do
    assert_equal KitchenDigestEmailJob::FALLBACK_RECIPIENTS, KitchenDigestEmailJob.recipients
  end
end
