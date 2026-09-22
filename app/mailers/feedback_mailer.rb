class FeedbackMailer < ApplicationMailer
  # The files ride along on the inbox copy only while the message stays under
  # this; past it the email links to the admin page instead.
  ATTACH_LIMIT = 20.megabytes

  # Rich's copy, for the agent44bot inbox: the message, who/where, and the files.
  def copy(feedback, to:)
    @feedback = feedback
    @admin_url = admin_feedbacks_url(anchor: ActionView::RecordIdentifier.dom_id(feedback))
    @attached = feedback.attachments.sum { |a| a.blob.byte_size } <= ATTACH_LIMIT
    if @attached
      feedback.attachments.each { |a| attachments[a.filename.to_s] = a.download }
    end
    mail to: to,
         reply_to: feedback.user.email_address.presence || ApplicationMailer.default[:reply_to],
         subject: "Feedback from #{feedback.user.display_identifier}: #{feedback.excerpt(60)}"
  end

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
end
