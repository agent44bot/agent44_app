# Monday 7am ET: email the owner a status report on the /admin/plan plans
# (progress, what was checked off in the last 7 days, what is next). Owner
# email is fixed; the plans are owner-only content.
class PlanStatusReportJob < ApplicationJob
  queue_as :default

  RECIPIENT = Admin::PlanController::OWNER_EMAIL

  def perform(now: Time.current)
    week_end = now.beginning_of_day
    week_start = week_end - 7.days
    plans = OwnerPlan.all

    PlanMailer.weekly_status(recipient: RECIPIENT, plans: plans, week_start: week_start, week_end: week_end).deliver_now
    Setting.touch_time("plan_status_report:last_sent_at")
    Rails.logger.info("PlanStatusReportJob: sent to #{RECIPIENT} (#{plans.map { |p| "#{p.slug} #{p.percent}%" }.join(", ")})")
  rescue => e
    Notification.notify!(
      level: "error",
      source: "plan_report",
      title: "PlanStatusReportJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end
end
