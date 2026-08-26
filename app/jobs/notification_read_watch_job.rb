# Read receipts. Watches specific Notification rows and pings Telegram once the
# recipient actually opens one, which is the only signal we have that an alert
# landed and was acted on: read_at is stamped when the notification is opened in
# the app, so a push glanced at on the lock screen never trips this.
#
# Off by default: does nothing until Setting "notification_read_watch:ids" lists
# notification ids (comma-separated). Add one from the console:
#
#   Setting.set("notification_read_watch:ids", "5214")
#
# Each id reports once and then removes itself from the list, so the job is
# idempotent, self-pruning, and a no-op on an empty list.
class NotificationReadWatchJob < ApplicationJob
  queue_as :default

  IDS_KEY = "notification_read_watch:ids".freeze

  def perform
    ids = watched_ids
    return if ids.empty?

    remaining = ids.reject { |id| settled?(id) }
    Setting.set(IDS_KEY, remaining.join(",")) unless remaining.size == ids.size
    remaining.size
  end

  private

  def watched_ids
    Setting.get(IDS_KEY).to_s.split(",").map(&:strip).reject(&:blank?).map(&:to_i)
  end

  # True when this id is done with: either it was read (and reported), or the
  # row is gone. A still-unread notification stays on the list.
  def settled?(id)
    notification = Notification.find_by(id: id)
    return true if notification.nil?
    return false if notification.read_at.nil?

    announce(notification)
    true
  end

  def announce(notification)
    who  = notification.user&.email_address.presence || "The recipient"
    when_read = notification.read_at.in_time_zone.strftime("%-I:%M %p on %-m/%-d")

    # Unsaved: this is the wire format for the Telegram message, not an alert
    # anyone needs in their in-app list. force: it is a receipt the owner asked
    # for by id, not the routine noise the global mute silences.
    receipt = Notification.new(
      level:  "info",
      source: "read_receipt",
      title:  "#{who} opened: #{notification.title}",
      body:   "Read at #{when_read}."
    )
    TelegramNotifier.send_alert(receipt, force: true)
  end
end
