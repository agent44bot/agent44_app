module Api
  module V1
    class JobsController < ApplicationController
      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

      def create
        jobs_data = params[:jobs] || [params[:job]]
        result = JobImporter.new(jobs_data).call
        render json: result
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
