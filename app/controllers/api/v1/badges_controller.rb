module Api
  module V1
    class BadgesController < ApplicationController
      skip_before_action :verify_authenticity_token

      def clear
        return head :unauthorized unless authenticated?

        user = Current.session.user
        user.notifications.unread.update_all(read_at: Time.current)
        ApnsPusher.clear_badge_for(user)

        head :no_content
      end

      # Reports the current user's unread state so the app can decide where to
      # land on icon tap: a single unread → straight to that notification's
      # url; multiple unread → /notifications inbox.
      def peek
        return head :unauthorized unless authenticated?

        user = Current.session.user
        unread = user.notifications.unread.recent
        latest = unread.first
        render json: {
          count: unread.count,
          url:   latest&.url
        }
      end
    end
  end
end
