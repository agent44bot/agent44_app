module Admin
  class NotificationsController < BaseController
    def index
      @notifications = Notification.recent.limit(100)
      @unread_count = Notification.unread.count
    end

    def update
      notification = Notification.find(params[:id])
      notification.mark_as_read!
      redirect_to admin_notifications_path, notice: "Marked as read."
    end

    def mark_all_read
      Notification.unread.update_all(read_at: Time.current)
      redirect_to admin_notifications_path, notice: "All notifications marked as read."
    end

    def destroy
      Notification.find(params[:id]).destroy
      redirect_to admin_notifications_path, notice: "Notification deleted."
    end
  end
end
