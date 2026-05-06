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
    end
  end
end
