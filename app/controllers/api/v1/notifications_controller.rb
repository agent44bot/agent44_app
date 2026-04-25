module Api
  module V1
    # Lightweight endpoint for external runners (smoke tests, deploy bots,
    # etc.) to push a Telegram notification through our existing
    # Notification.notify! pipeline without going through the per-agent
    # status debounce. Used by NYK smoke for progress pings.
    class NotificationsController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access
      before_action :authenticate_api_token

      # POST /api/v1/notifications
      # Body: { source: "smoke_progress", title: "...", body: "...", level: "info", telegram: true }
      def create
        notification = Notification.notify!(
          level: (params[:level].presence || "info"),
          source: (params[:source].presence || "external"),
          title: params[:title].to_s,
          body: params[:body].presence,
          telegram: ActiveModel::Type::Boolean.new.cast(params.fetch(:telegram, true))
        )

        if notification
          render json: { id: notification.id, source: notification.source }, status: :created
        else
          render json: { error: "Notification creation failed" }, status: :unprocessable_entity
        end
      end
    end
  end
end
