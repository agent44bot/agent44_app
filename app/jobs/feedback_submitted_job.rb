# Fans a new Feedback out: a push to Rich that opens the item on the board,
# and a "got it" email to the sender. Runs after commit so the attachments are
# already stored. (The agent44bot inbox copy was dropped 2026-09-22: the board
# is the record.)
class FeedbackSubmittedJob < ApplicationJob
  queue_as :default

  def perform(feedback)
    FeedbackAlerts.push(feedback, "Feedback from #{feedback.user.display_identifier}", feedback.excerpt(200))
    FeedbackMailer.received(feedback).deliver_later if feedback.user.email_address.present?
  end
end
