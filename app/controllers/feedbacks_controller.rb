# The Feedback button: any signed-in user, any workspace. They write a
# message, attach photos or files, and it lands with Rich (see Feedback).
# The list shows what they have sent and where each item stands.
class FeedbacksController < ApplicationController
  rate_limit to: 10, within: 1.hour, only: :create, by: RATE_LIMIT_BY_CLIENT_IP,
             with: -> { redirect_to new_feedback_path, alert: "That's a lot of feedback at once. Please try again in a bit." }

  def index
    @feedbacks = Current.user.feedbacks.recent_first.with_attached_attachments
  end

  def new
    @feedback = Feedback.new(page_url: same_site_path(params[:from].presence || request.referer))
  end

  def create
    @feedback = Current.user.feedbacks.new(
      message: params.dig(:feedback, :message),
      page_url: same_site_path(params.dig(:feedback, :page_url))
    )
    @feedback.workspace = workspace_for(@feedback.page_url)
    files = Array(params.dig(:feedback, :attachments)).compact_blank
    @feedback.attachments.attach(files) if files.any?

    if @feedback.save
      redirect_to feedbacks_path, notice: "Thanks! Your feedback was sent. We'll email you when it's done."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # The sender's answer to Rich's question: back to the agent for a new plan.
  def answer
    feedback = Current.user.feedbacks.find(params[:id])
    feedback.answer!(params[:answer])
    redirect_to feedbacks_path(anchor: helpers.dom_id(feedback)), notice: "Thanks! Your answer was sent."
  rescue Feedback::InvalidTransition => e
    redirect_to feedbacks_path, alert: e.message
  end

  private

  # Keep only a path on this site ("/nykitchen/packets/90/edit"), never an
  # outside URL, so the admin page and emails can link to it safely.
  def same_site_path(url)
    uri = URI.parse(url.to_s)
    return nil if uri.host.present? && uri.host != request.host
    path = uri.path.presence or return nil
    return nil unless path.start_with?("/") && !path.start_with?("/feedback")
    [ path, uri.query ].compact.join("?")
  rescue URI::InvalidURIError
    nil
  end

  # The workspace the user was in: the first path segment when it is one of
  # theirs, else their only workspace, else none.
  def workspace_for(path)
    workspaces = Current.user.workspaces
    slug = path.to_s.split("/")[1]
    (slug.present? && workspaces.find_by(slug: slug)) ||
      (workspaces.one? ? workspaces.first : nil)
  end
end
