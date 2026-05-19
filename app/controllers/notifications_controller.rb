class NotificationsController < ApplicationController
  def index
    user = Current.user
    @notifications = user.notifications.recent.limit(50)
    @unread_count = user.notifications.unread.count
    user.notifications.unread.update_all(read_at: Time.current)
  end
end
