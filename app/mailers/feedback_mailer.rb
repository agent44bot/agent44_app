class FeedbackMailer < ApplicationMailer
  # "Got it" to the sender.
  def received(feedback)
    @feedback = feedback
    @list_url = feedbacks_url
    mail to: feedback.user.email_address, subject: "We got your feedback"
  end

  # Sent once, when Rich marks the feedback shipped.
  def shipped(feedback)
    @feedback = feedback
    @list_url = feedbacks_url
    mail to: feedback.user.email_address, subject: "Your feedback is live"
  end

  # Rich's question about their feedback; they answer on their feedback page.
  def question(feedback)
    @feedback = feedback
    @question = feedback.thread.reverse.find { |t| t["kind"] == "question" }&.dig("body")
    @answer_url = feedbacks_url(anchor: ActionView::RecordIdentifier.dom_id(feedback))
    mail to: feedback.user.email_address, subject: "A quick question about your feedback"
  end

  # Closed without a change, with Rich's note saying why.
  def closed(feedback)
    @feedback = feedback
    @list_url = feedbacks_url
    mail to: feedback.user.email_address, subject: "About your feedback"
  end
end
