# Fans a new Feedback out: a push (and Telegram, unless muted) to Rich, an
# email copy with the files to the agent44bot inbox, and a "got it" email to
# the sender. Runs after commit so the attachments are already stored.
class FeedbackSubmittedJob < ApplicationJob
  queue_as :default

  COPY_EMAIL_KEY = "feedback.copy_email".freeze
  DEFAULT_COPY_EMAIL = "agent44bot@gmail.com".freeze
  ALERT_EMAIL_KEY = FeedbackAlerts::ALERT_EMAIL_KEY

  def perform(feedback)
    FeedbackAlerts.push(feedback, "Feedback from #{feedback.user.display_identifier}", feedback.excerpt(200))
    FeedbackMailer.copy(feedback, to: copy_email).deliver_later
    FeedbackMailer.received(feedback).deliver_later if feedback.user.email_address.present?
  end

  private

  def copy_email
    Setting.get(COPY_EMAIL_KEY).to_s.strip.presence || DEFAULT_COPY_EMAIL
  end
end
