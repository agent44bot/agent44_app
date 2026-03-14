module Api
  module V1
    class JobsController < ApplicationController
      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

      def create
        jobs_data = params[:jobs] || [params[:job]]
        created = 0

        jobs_data.each do |jp|
          job = Job.find_or_initialize_by(source: jp[:source], url: jp[:url])
          if job.new_record?
            job.assign_attributes(
              title: jp[:title],
              company: jp[:company],
              location: jp[:location],
              salary: jp[:salary],
              description: jp[:description],
              category: jp[:category],
              posted_at: jp[:posted_at].present? ? Time.zone.parse(jp[:posted_at].to_s) : Time.current,
              active: true
            )
            created += 1 if job.save
          end
        end

        render json: { created: created, total: jobs_data.size }
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
