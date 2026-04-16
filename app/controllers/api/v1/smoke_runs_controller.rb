module Api
  module V1
    class SmokeRunsController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access
      before_action :authenticate_api_token

      # POST /api/v1/smoke_runs
      # Body: {
      #   name: "nyk_calendar_nav",
      #   status: "passed" | "failed",
      #   started_at: "2026-04-16T13:00:00Z",
      #   ended_at:   "2026-04-16T13:00:18Z",
      #   duration_ms: 18000,
      #   summary: "42/55/21/3 events round-tripped",
      #   error_message: "..."  # optional
      # }
      def create
        run = SmokeTestRun.create!(run_params)
        Rails.cache.delete("smoke_runs/recent")
        render json: run_json(run), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def run_params
        params.permit(
          :name, :status, :started_at, :ended_at,
          :duration_ms, :summary, :error_message
        )
      end

      def run_json(run)
        {
          id: run.id,
          name: run.name,
          status: run.status,
          started_at: run.started_at,
          ended_at: run.ended_at,
          duration_ms: run.duration_ms,
          summary: run.summary,
          error_message: run.error_message
        }
      end
    end
  end
end
