module Api
  module V1
    class StatsController < ApplicationController
      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

      def users
        total_users = User.count
        today_signups = User.where("created_at >= ?", Time.current.beginning_of_day).count
        yesterday_signups = User.where(created_at: 1.day.ago.beginning_of_day..1.day.ago.end_of_day).count
        week_signups = User.where("created_at >= ?", 7.days.ago.beginning_of_day).count

        recent_users = User.where("created_at >= ?", 1.day.ago.beginning_of_day)
          .order(created_at: :desc)
          .pluck(:display_name, :email_address, :created_at)
          .map { |name, email, created| { name: name, email: email, signed_up: created } }

        render json: {
          total_users: total_users,
          today: today_signups,
          yesterday: yesterday_signups,
          last_7_days: week_signups,
          recent_signups: recent_users
        }
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
