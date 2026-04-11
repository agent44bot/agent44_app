module Api
  module V1
    class ScrapersController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

      # Rate limit: 50 update requests per hour per IP
      rate_limit to: 50, within: 1.hour, by: -> { request.remote_ip }, only: :update

      def update
        source = ScraperSource.find_by!(slug: params[:id])
        source.update!(
          last_run_at: params[:last_run_at],
          last_run_status: params[:last_run_status],
          last_run_jobs_found: params[:last_run_jobs_found],
          last_run_error: params[:last_run_error]
        )
        render json: { status: "ok", slug: source.slug }
      end
    end
  end
end
