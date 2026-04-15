module Api
  module V1
    class DeploysController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

      # POST /api/v1/deploy — Queue a deploy task for Knox
      def create
        app = params[:app].presence || "agent44-app"
        requested_by = params[:requested_by].presence || "api"

        message = AgentMessage.create!(
          role: "user",
          agent: "Knox \u{1f512}",
          content: "deploy:#{app}",
          status: "pending"
        )

        # Update Knox status to busy
        knox = Agent.find_by(name: "Knox \u{1f512}")
        knox&.update!(status: "busy", current_task: "Deploying #{app}", last_active_at: Time.current)
        Rails.cache.delete("agents/ordered")

        Notification.notify!(
          level: "info",
          source: "deploy",
          title: "Deploy requested",
          body: "#{requested_by} requested deploy of #{app}",
          telegram: true
        )

        render json: { id: message.id, status: "queued", app: app }
      end
    end
  end
end
