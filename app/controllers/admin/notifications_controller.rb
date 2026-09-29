module Admin
  class NotificationsController < BaseController
    def index
      @alerts = Notification.collapse(feed.recent.limit(300)).first(100)
      @unread_count = Notification.admin_unread_count(Current.user)
    end

    def update
      alert_copies.unread.update_all(read_at: Time.current)
      redirect_to admin_notifications_path, notice: "Marked as read."
    end

    # Only the admin's own feed: other people's per-user copies drive their
    # own unread badges, so the admin page must never clear them.
    def mark_all_read
      feed.unread.update_all(read_at: Time.current)
      redirect_to admin_notifications_path, notice: "All notifications marked as read."
    end

    def destroy
      alert_copies.destroy_all
      redirect_to admin_notifications_path, notice: "Notification deleted."
    end

    private

    def feed
      Notification.admin_feed(Current.user)
    end

    def alert_copies
      feed.find(params[:id]).copies_in(feed)
    end
  end
end
