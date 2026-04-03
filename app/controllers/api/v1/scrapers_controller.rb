module Api
  module V1
    class ScrapersController < ApplicationController
      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

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

      private

      def authenticate_api_token
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")
        unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, ENV.fetch("API_TOKEN", ""))
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end
    end
  end
end
