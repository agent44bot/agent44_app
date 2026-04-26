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

      # PUT /api/v1/smoke_runs/:id/video
      # Accepts video + thumbnail + page_source + trace as multipart parts.
      # Path stays "/video" for back-compat with older smoke clients.
      def video
        run = SmokeTestRun.find(params[:id])

        run.video.attach(params[:video])             if params[:video]
        run.thumbnail.attach(params[:thumbnail])     if params[:thumbnail]
        run.page_source.attach(params[:page_source]) if params[:page_source]
        run.trace.attach(params[:trace])             if params[:trace]

        # Retention policy:
        #   - Keep ALL failed run artifacts (for debugging)
        #   - Keep only the LATEST passing run's artifacts
        if run.status == "passed"
          SmokeTestRun.where(status: "passed").where.not(id: run.id).find_each do |old_run|
            old_run.video.purge        if old_run.video.attached?
            old_run.thumbnail.purge    if old_run.thumbnail.attached?
            old_run.page_source.purge  if old_run.page_source.attached?
            old_run.trace.purge        if old_run.trace.attached?
          end
        end

        render json: {
          status: "ok",
          video_attached:       run.video.attached?,
          thumbnail_attached:   run.thumbnail.attached?,
          page_source_attached: run.page_source.attached?,
          trace_attached:       run.trace.attached?
        }
      end

      private

      def run_params
        params.permit(
          :name, :status, :started_at, :ended_at,
          :duration_ms, :summary, :error_message, :console_errors
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
          error_message: run.error_message,
          console_errors: run.console_errors
        }
      end
    end
  end
end
