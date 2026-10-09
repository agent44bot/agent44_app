# Once a day, re-pushes Rich about every customer item that has sat on his
# call (plan ready, ready to merge, or stuck) for over a day. Caitlin's two
# items waited three days at "Plan ready" after the first push got read and
# forgotten (2026-10-06).
class FeedbackNudgeJob < ApplicationJob
  queue_as :default

  WAIT = 24.hours

  def perform
    Feedback.needs_rich.includes(:user, :workspace).find_each do |feedback|
      next unless feedback.from_customer? && feedback.waiting_since <= WAIT.ago

      days = ((Time.current - feedback.waiting_since) / 1.day).floor
      title = "#{feedback.user.display_identifier}'s feedback has waited #{days} #{"day".pluralize(days)}"
      FeedbackAlerts.push(feedback, title, "#{feedback.status_label}: #{feedback.excerpt(200)}", level: "warning")
    end
  end
end
