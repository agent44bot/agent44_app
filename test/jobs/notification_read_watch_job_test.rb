require "test_helper"
require "minitest/mock"

# NotificationReadWatchJob pings Telegram when a watched notification is opened.
# No HTTP leaves the process: the test env has no TELEGRAM_* creds, so the
# notifier early-returns, and the assertions are on the watch list it prunes.
class NotificationReadWatchJobTest < ActiveJob::TestCase
  setup do
    Setting.delete_all
    @user = User.create!(email_address: "rw-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @notification = Notification.create!(level: "info", source: "social_engagement",
                                         title: "+1 like on your X post", user: @user)
  end

  test "does nothing when no ids are watched" do
    assert_nil NotificationReadWatchJob.perform_now
  end

  test "an unread notification stays on the watch list and sends nothing" do
    Setting.set(NotificationReadWatchJob::IDS_KEY, @notification.id.to_s)

    TelegramNotifier.stub(:send_alert, ->(*, **) { flunk "must not report an unread notification" }) do
      NotificationReadWatchJob.perform_now
    end

    assert_equal @notification.id.to_s, Setting.get(NotificationReadWatchJob::IDS_KEY)
  end

  test "reports once when opened, then removes itself from the list" do
    Setting.set(NotificationReadWatchJob::IDS_KEY, @notification.id.to_s)
    @notification.mark_as_read!

    sent = []
    TelegramNotifier.stub(:send_alert, ->(note, **opts) { sent << [ note, opts ] }) do
      NotificationReadWatchJob.perform_now
    end

    assert_equal 1, sent.size
    receipt, opts = sent.first
    assert_includes receipt.title, @user.email_address
    assert_includes receipt.title, "+1 like on your X post"
    assert opts[:force], "a read receipt must bypass the global Telegram mute"
    assert_predicate receipt, :new_record?, "the receipt is a wire format, not an in-app alert"
    assert_equal "", Setting.get(NotificationReadWatchJob::IDS_KEY)

    # Second run has nothing left to report.
    TelegramNotifier.stub(:send_alert, ->(*, **) { flunk "must report only once" }) do
      NotificationReadWatchJob.perform_now
    end
  end

  test "a deleted notification is dropped from the list without reporting" do
    Setting.set(NotificationReadWatchJob::IDS_KEY, "#{@notification.id},999999")
    @notification.destroy!

    TelegramNotifier.stub(:send_alert, ->(*, **) { flunk "nothing to report" }) do
      NotificationReadWatchJob.perform_now
    end

    assert_equal "", Setting.get(NotificationReadWatchJob::IDS_KEY)
  end
end
