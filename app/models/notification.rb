class Notification < ApplicationRecord
  LEVELS = %w[info success warning error].freeze

  belongs_to :user, optional: true

  validates :level, inclusion: { in: LEVELS }
  validates :source, :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # The admin notifications page: log (user-less) copies plus the viewing
  # admin's own. A broadcast alert (e.g. kitchen_tickets) also saves one copy
  # per recipient so each person's badge counts their own unread; those are
  # their inbox, not the admin log, and listing them showed every alert ~10x.
  scope :admin_feed, ->(user) { where(user_id: [ nil, user&.id ]) }

  # Copies of one alert (the log copy + the admin's own) share source, title
  # and body and are written in the same moment; this key collapses them.
  ALERT_MINUTE_SQL = "strftime('%Y-%m-%d %H:%M', notifications.created_at)".freeze

  def alert_key
    [ source, title, body, created_at.utc.strftime("%Y-%m-%d %H:%M") ]
  end

  # Collapse copies of the same alert into one row, keeping newest-first order.
  # Returns arrays of notifications; the first of each is the one to display.
  def self.collapse(notifications)
    notifications.group_by(&:alert_key).values
  end

  # Unread alerts in the admin feed, counting each alert once.
  def self.admin_unread_count(user)
    admin_feed(user).unread.distinct.count(Arel.sql("source || '|' || title || '|' || COALESCE(body, '') || '|' || #{ALERT_MINUTE_SQL}"))
  end

  # All copies of this alert within scope.
  def copies_in(scope)
    minute = created_at.utc.beginning_of_minute
    scope.where(source: source, title: title, body: body, created_at: minute...(minute + 1.minute))
  end

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end

  # How this alert reads as a chat message in a Buzz room.
  def buzz_text
    icon = { "error" => "🔴", "warning" => "🟡", "success" => "🟢" }.fetch(level, "🔵")
    [ "#{icon} #{title}", body.presence ].compact.join("\n")
  end

  # Convenience: create + optionally push to Telegram / mobile (iOS + Android).
  # Pass apns_user to target a specific user's devices; nil = all devices.
  # The notification record is tied to apns_user so that user's unread count
  # drives the iOS app icon badge. The `apns:` flag means "send a mobile push";
  # it fans out to both APNs (iOS) and FCM (Android), each gated by the user's
  # per-platform preference. Pass `workspace:` to also honor that user's
  # per-workspace push opt-out (e.g. muting NY Kitchen alerts).
  # `buzz:` mirrors the alert into a Buzz channel as a signed event; pass
  # `buzz_agent:` to sign as a named agent (e.g. "vlad") rather than the app.
  def self.notify!(level:, source:, title:, body: nil, telegram: false, apns: false, apns_url: nil, apns_subtitle: nil, apns_user: nil, workspace: nil, buzz: false, buzz_agent: nil)
    notification = create!(level: level, source: source, title: title, body: body, user: apns_user, url: apns_url)
    TelegramNotifier.send_alert(notification) if telegram
    BuzzPublishJob.perform_later(notification.buzz_text, agent: buzz_agent) if buzz && Buzz.enabled?
    if apns
      ApnsPusher.send_alert(notification, url: apns_url, subtitle: apns_subtitle, user: apns_user, workspace: workspace)
      FcmPusher.send_alert(notification, url: apns_url, subtitle: apns_subtitle, user: apns_user, workspace: workspace)
    end
    notification
  rescue => e
    Rails.logger.error("Notification.notify! failed: #{e.message}")
    nil
  end
end
