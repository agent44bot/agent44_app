module Admin
  # Rich's Feedback inbox. The list shows everything, open items first; each
  # item's page carries the buttons for its step in the pipeline
  # (docs/feedback_pipeline.md): Work on it / Ask them / Close after a plan,
  # Merge it / Request changes once the PR is green, Mark Live by hand.
  class FeedbacksController < BaseController
    before_action :set_feedback, except: :index

    def index
      @status = params[:status].presence_in(Feedback::STATUSES)
      scope = Feedback.includes(:user, :workspace).with_attached_attachments.recent_first
      @feedbacks = @status ? scope.where(status: @status) : scope.limit(200)
      @open_count = Feedback.open.count
    end

    def show
    end

    # Work on it (1).
    def approve = transition("Approved. The agent will start building.") { @feedback.approve! }

    def ask
      transition("Question emailed to #{@feedback.user.display_identifier}.") { @feedback.ask!(params[:question]) }
    end

    def close = transition("Closed.") { @feedback.close!(params[:note]) }

    def request_changes
      transition("Sent back to the agent.") { @feedback.request_changes!(params[:note]) }
    end

    # Merge it (2).
    def merge
      transition("Merge requested. You'll get a push when it's live.") do
        @feedback.request_merge!(params[:sha], note: params[:note])
      end
    end

    # Mark Live by hand, for items Rich fixed himself. Emails the sender once.
    def ship = transition("Marked Live.") { @feedback.ship!(params[:note]) }

    def retry = transition("Retrying.") { @feedback.retry! }

    private

    def set_feedback
      @feedback = Feedback.find(params[:id])
    end

    def transition(notice)
      yield
      redirect_to admin_feedback_path(@feedback), notice: notice
    rescue Feedback::InvalidTransition, ActiveRecord::RecordInvalid => e
      redirect_to admin_feedback_path(@feedback), alert: e.message
    end
  end
end
