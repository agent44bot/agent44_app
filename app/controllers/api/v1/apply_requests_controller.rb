module Api
  module V1
    # The queue the Mac-Mini Playwright "apply runner" talks to. It pulls the
    # pending requests (queued + in-progress so nothing gets stuck) plus Rich's
    # application profile to fill forms with, then PATCHes status back as it
    # opens each posting and fills it to the submit button. Nothing is submitted
    # by the runner; Rich clicks submit.
    class ApplyRequestsController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

      # GET /api/v1/apply_requests
      def index
        requests = ApplyRequest.pending.includes(:job).order(:requested_at)
        render json: {
          profile: JobMatcher.profile["application"] || {},
          requests: requests.map { |r| serialize(r) }
        }
      end

      # PATCH /api/v1/apply_requests/:id
      # Body: { status: "opened" | "filled" | "applied" | "error" | "skipped", notes: "..." }
      def update
        req = ApplyRequest.find(params[:id])
        attrs = { notes: params[:notes] }.compact
        attrs[:status] = params[:status] if params[:status].present?
        case params[:status]
        when "opened"  then attrs[:opened_at]  = Time.current
        when "filled"  then attrs[:filled_at]  = Time.current
        when "applied" then attrs[:applied_at] = Time.current
        end
        req.update!(attrs)
        render json: serialize(req)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Apply request not found" }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def serialize(req)
        job = req.job
        {
          id: req.id,
          status: req.status,
          notes: req.notes,
          job: {
            id: job.id, title: job.title, company: job.company, url: job.url,
            location: job.location, salary: job.salary
          }
        }
      end
    end
  end
end
