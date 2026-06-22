module Api
  module V1
    class DeviceTokensController < ApplicationController
      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      # POST /api/v1/device_tokens
      # Body: { token: "apns-hex-token", platform: "ios" }
      # Accepts requests from the Capacitor native shell (no auth needed —
      # only the native app can obtain an APNs device token).
      PLATFORMS = %w[ios android].freeze

      def create
        device_token = DeviceToken.find_or_initialize_by(token: params[:token])
        device_token.platform = PLATFORMS.include?(params[:platform]) ? params[:platform] : "ios"
        device_token.active = true
        if params.key?(:user_id)
          device_token.user_id = resolve_user_id(params[:user_id])
        elsif authenticated?
          device_token.user_id = Current.user.id
        end
        device_token.save!

        # One greppable line per registration: which token (prefix), which
        # user (nil = orphan, e.g. signed-out or display device), new or
        # re-registered. Saved hours in the 2026-06-05 push-delivery hunt.
        Rails.logger.info(
          "DeviceToken register: #{device_token.token[0, 12]}... " \
          "user=#{device_token.user_id.inspect} #{device_token.previously_new_record? ? "created" : "re-registered"}"
        )

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
