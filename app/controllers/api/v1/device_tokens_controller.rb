module Api
  module V1
    class DeviceTokensController < ApplicationController
      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      # POST /api/v1/device_tokens
      # Body: { token: "apns-hex-token", platform: "ios" }
      # Accepts requests from the Capacitor native shell (no auth needed —
      # only the native app can obtain an APNs device token).
      def create
        device_token = DeviceToken.find_or_initialize_by(token: params[:token])
        device_token.platform = params[:platform] || "ios"
        device_token.active = true
        device_token.user_id = resolve_user_id(params[:user_id]) if params.key?(:user_id)
        device_token.save!

        render json: { id: device_token.id, token: device_token.token, user_id: device_token.user_id }, status: :created
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def resolve_user_id(raw)
        return nil if raw.blank?
        User.where(id: raw).pick(:id)
      end
    end
  end
end
