module Admin
  # Rich's Feedback board: Pre-dev, Dev, Post-dev, Review PR, Deploy, Done
  # (docs/feedback_pipeline.md). Items can be added, edited, deleted and
  # moved by hand (back to Pre-dev, Live, Closed). Each item's page carries
  # the buttons for its step: Work on it / Ask them after a plan, Merge it /
  # Request changes once the PR is green.
  class FeedbacksController < BaseController
    before_action :set_feedback, except: %i[index new create]

    DONE_SHOWN = 20 # the Done column shows the most recent only

    # The board: one column per stage. Done shows the latest DONE_SHOWN.
    def index
      items = Feedback.includes(:user, :workspace).recent_first
      open_items = items.where.not(status: Feedback::DONE).to_a
      @columns = Feedback::STAGES.keys.index_with { [] }
      open_items.each { |f| @columns[f.stage] << f }
      @columns["done"] = items.where(status: Feedback::DONE).limit(DONE_SHOWN).to_a
      @waiting_count = open_items.count(&:waiting_on_rich?)
    end

    def show
    end

    # + New item: Rich's own ideas go straight onto the board, with no push
    # or "got it" email to himself.
    def new
      @feedback = Feedback.new
    end

    def create
      @feedback = Current.user.feedbacks.new(message: params.dig(:feedback, :message), skip_notifications: true)
      files = Array(params.dig(:feedback, :attachments)).compact_blank
      @feedback.attachments.attach(files) if files.any?
      if @feedback.save
        redirect_to admin_feedback_path(@feedback), notice: "Added to Pre-dev."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @feedback.update(message: params.dig(:feedback, :message))
        redirect_to admin_feedback_path(@feedback), notice: "Saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @feedback.destroy!
      redirect_to admin_feedbacks_path, notice: "Deleted."
    end

    # Back to Pre-dev for a fresh plan (also reopens a Done item).
    def reset = transition("Back in Pre-dev. The agent will re-plan it.") { @feedback.reset! }

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
