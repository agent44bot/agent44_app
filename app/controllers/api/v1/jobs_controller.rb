module Api
  module V1
    class JobsController < ApplicationController
      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

      def create
        jobs_data = params[:jobs] || [params[:job]]
        created = 0
        updated = 0

        jobs_data.each do |jp|
          # Skip if this exact source+url already exists
          next if JobSource.exists?(source: jp[:source], url: jp[:url])

          # Check for cross-source duplicate via normalized title+company
          norm_title = Job.normalize_title(jp[:title])
          norm_company = Job.normalize_company(jp[:company])
          existing_job = Job.find_by(normalized_title: norm_title, normalized_company: norm_company) if norm_title.present?

          if existing_job
            existing_job.job_sources.create(
              source: jp[:source],
              url: jp[:url],
              external_id: jp[:external_id]
            )
            existing_job.update(description: jp[:description]) if existing_job.description.blank? && jp[:description].present?
            existing_job.update(salary: jp[:salary]) if existing_job.salary.blank? && jp[:salary].present?
            existing_job.update(location: jp[:location]) if existing_job.location.blank? && jp[:location].present?
            updated += 1
          else
            job = Job.new(
              title: jp[:title],
              company: jp[:company],
              location: jp[:location],
              salary: jp[:salary],
              description: jp[:description],
              category: jp[:category],
              source: jp[:source],
              url: jp[:url],
              external_id: jp[:external_id],
              posted_at: jp[:posted_at].present? ? Time.zone.parse(jp[:posted_at].to_s) : Time.current,
              active: true
            )
            if job.save
              job.job_sources.create!(
                source: jp[:source],
                url: jp[:url],
                external_id: jp[:external_id]
              )
              created += 1
            end
          end
        end

        render json: { created: created, updated: updated, total: jobs_data.size }
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
