module Api
  module V1
    class StatsController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

      # Rate limit: 100 requests per hour per IP
      rate_limit to: 100, within: 1.hour, by: -> { request.remote_ip }, only: :users

      def users
        total_users = User.count
        today_signups = User.where("created_at >= ?", Time.current.beginning_of_day).count
        yesterday_signups = User.where(created_at: 1.day.ago.beginning_of_day..1.day.ago.end_of_day).count
        week_signups = User.where("created_at >= ?", 7.days.ago.beginning_of_day).count

        # Only return aggregated counts and display names — no emails or PII
        recent_users = User.where("created_at >= ?", 1.day.ago.beginning_of_day)
          .order(created_at: :desc)
          .limit(25)
          .pluck(:display_name, :created_at)
          .map { |name, created| { name: name, signed_up: created } }

        render json: {
          total_users: total_users,
          today: today_signups,
          yesterday: yesterday_signups,
          last_7_days: week_signups,
          recent_signups: recent_users
        }
      end
    end
  end
end
