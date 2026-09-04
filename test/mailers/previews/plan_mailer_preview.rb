# http://localhost:3000/rails/mailers/plan_mailer/weekly_status
class PlanMailerPreview < ActionMailer::Preview
  def weekly_status
    now = Time.current
    PlanMailer.weekly_status(recipient: Admin::PlanController::OWNER_EMAIL, plans: OwnerPlan.all,
                             week_start: now.beginning_of_day - 7.days, week_end: now.beginning_of_day)
  end
end
