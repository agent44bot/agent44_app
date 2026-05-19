module Api
  module V1
    class BadgesController < ApplicationController
      # API endpoints — never participate in the post-login redirect dance.
      # If the JS calls these before the user is authenticated, return 401
      # JSON so the fetch quietly drops it instead of polluting
      # session[:return_to_after_authenticating] with /api/v1/badge/clear.
      # That pollution caused a 404 right after Face ID sign-in because the
      # browser followed the post-auth redirect to a POST-only endpoint as GET.
      allow_unauthenticated_access
      skip_before_action :verify_authenticity_token

      def clear
        return render(json: { error: "unauthorized" }, status: :unauthorized) unless authenticated?

        user = Current.user
        user.notifications.unread.update_all(read_at: Time.current)
        ApnsPusher.clear_badge_for(user)

        head :no_content
      end

      # Reports the current user's unread state so the app can decide where to
      # land on icon tap: a single unread → straight to that notification's
      # url; multiple unread → /notifications inbox.
      def peek
        return render(json: { error: "unauthorized" }, status: :unauthorized) unless authenticated?

        user = Current.user
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
