require "test_helper"

# Monday owner email summarizing the /admin/plan plans.
class PlanStatusReportJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup { Setting.delete_all }

  test "emails the owner with per-plan progress, last week's check-offs, and next steps" do
    travel_to Time.zone.parse("2026-09-14 07:00") do # Monday
      Setting.set("growth_2027:done:multitenant", (Time.current - 2.days).iso8601)  # inside the week
      Setting.set("growth_2027:done:bundle", (Time.current - 9.days).iso8601)       # before the week

      assert_emails(1) { PlanStatusReportJob.perform_now }
      mail = ActionMailer::Base.deliveries.last

      assert_equal [ "botwhisperer@hey.com" ], mail.to
      assert_match "2027 growth", mail.subject
      assert_match "1 done", mail.subject

      body = mail.body.to_s
      assert_match "2027 growth plan", body
      assert_match "June 2026 plan", body
      assert_match "2 of 11 done", body
      assert_match "Finish the multi-tenant refactor", body          # checked off this week
      assert_match "Sat Sep 12", body
      assert_match "Close Gems of Eden", body                        # next up
      assert_match "/admin/plan", body
      assert_no_match(/—|–/, body)
      assert Setting.time("plan_status_report:last_sent_at")
    end
  end

  test "a fully completed plan reads as done instead of listing steps" do
    OwnerPlan.find("june-2026").steps.each { |s| Setting.touch_time("june_plan:done:#{s.id}") }
    PlanStatusReportJob.perform_now
    body = ActionMailer::Base.deliveries.last.body.to_s
    assert_match "All done. Nothing left on this plan.", body
    assert_no_match "June 2026 DBA", ActionMailer::Base.deliveries.last.subject
  end
end
