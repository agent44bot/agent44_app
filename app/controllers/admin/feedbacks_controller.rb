module Admin
  # Rich's inbox for Feedback: everything sent, newest first, open items on
  # top. Moving one to "Live" emails the sender (once), with the optional note.
  class FeedbacksController < BaseController
    def index
      @status = params[:status].presence_in(Feedback::STATUSES)
      scope = Feedback.includes(:user, :workspace).with_attached_attachments.recent_first
      @feedbacks = @status ? scope.where(status: @status) : scope.limit(200)
      @open_count = Feedback.open.count
    end

    def update
      feedback = Feedback.find(params[:id])
      status = params.dig(:feedback, :status).presence_in(Feedback::STATUSES) || feedback.status
      note = params.dig(:feedback, :reply)

      if status == "shipped"
        feedback.ship!(note)
      else
        feedback.update!(status: status, reply: note.presence || feedback.reply)
      end
      redirect_to admin_feedbacks_path(anchor: helpers.dom_id(feedback)), notice: "Updated: #{feedback.status_label}."
    end
  end
end
