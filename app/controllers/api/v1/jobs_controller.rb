module Api
  module V1
    class JobsController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

      # Rate limit: 50 create requests per hour per client IP
      rate_limit to: 50, within: 1.hour, by: RATE_LIMIT_BY_CLIENT_IP, only: :create

      def create
        jobs_data = params[:jobs] || [ params[:job] ]
        result = JobImporter.new(jobs_data).call
        render json: result
      end
    end
  end
end
