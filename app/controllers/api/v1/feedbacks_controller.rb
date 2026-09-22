module Api
  module V1
    # The queue the Mac mini feedback agent talks to (docs/feedback_pipeline.md).
    # It pulls items waiting on it, claims one, and reports back: a plan, the
    # PR as it builds, the merged-and-deployed SHA, or an error. Rich's two
    # gates (Work on it, Merge it) live in the admin UI, never here.
    class FeedbacksController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token
      before_action :set_feedback, except: :queue

      # GET /api/v1/feedbacks/queue
      def queue
        items = Feedback.agent_queue.includes(:user, :workspace).with_attached_attachments
        render json: { feedbacks: items.map { |f| serialize(f) } }
      end

      # POST /api/v1/feedbacks/:id/claim
      def claim = report { @feedback.claim! }

      # POST /api/v1/feedbacks/:id/plan  { plan:, question: }
      def plan = report { @feedback.record_plan!(params[:plan], question: params[:question]) }

      # POST /api/v1/feedbacks/:id/pr  { number:, url:, head_sha:, checks:, summary:, ship_note: }
      def pr
        report do
          @feedback.record_pr!(number: params[:number], url: params[:url], head_sha: params[:head_sha],
                               checks: params[:checks], summary: params[:summary], ship_note: params[:ship_note])
        end
      end

      # POST /api/v1/feedbacks/:id/shipped  { sha: }
      def shipped = report { @feedback.record_shipped!(params[:sha]) }

      # POST /api/v1/feedbacks/:id/error  { message: }
      def error = report { @feedback.record_error!(params[:message]) }

      private

      def set_feedback
        @feedback = Feedback.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Feedback not found" }, status: :not_found
      end

      def report
        yield
        render json: serialize(@feedback.reload)
      rescue Feedback::InvalidTransition, ActiveRecord::RecordInvalid => e
        render json: { error: e.message, feedback: serialize(@feedback.reload) }, status: :conflict
      end

      def serialize(f)
        {
          id: f.id, status: f.status, step: f.agent_step,
          message: f.message, page_url: f.page_url,
          sender: f.user.display_identifier, workspace: f.workspace&.slug,
          thread: f.thread, plan: f.plan,
          pr: { number: f.pr_number, url: f.pr_url, head_sha: f.pr_head_sha, checks: f.pr_checks, summary: f.pr_summary },
          merge_requested_sha: f.merge_requested_sha, ship_note: f.ship_note,
          agent_error: f.agent_error, agent_claimed_at: f.agent_claimed_at&.iso8601,
          attachments: f.attachments.map { |a|
            { filename: a.filename.to_s, content_type: a.content_type, byte_size: a.byte_size,
              url: rails_blob_url(a, disposition: "attachment") }
          },
          admin_url: admin_feedback_url(f), created_at: f.created_at.iso8601
        }
      end
    end
  end
end
