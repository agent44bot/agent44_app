# Monday morning status of the owner's plans (/admin/plan): progress per plan,
# what was checked off last week, and what is next. Owner-only mail.
class PlanMailer < ApplicationMailer
  def weekly_status(recipient:, plans:, week_start:, week_end:)
    @plans = plans
    @week_start = week_start
    @week_end = week_end
    @done_this_week = plans.to_h { |p| [ p.slug, p.done_between(week_start, week_end) ] }
    @plan_url = admin_plan_url

    open_plans = plans.reject(&:complete?)
    headline = open_plans.map { |p| "#{p.tab} #{p.percent}%" }.join(" · ")
    checked = @done_this_week.values.sum(&:size)
    mail(
      to: recipient,
      subject: "Plans this week: #{headline}#{" · #{checked} done" if checked.positive?}"
    )
  end
end
