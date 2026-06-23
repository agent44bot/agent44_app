class Notification < ApplicationRecord
  LEVELS = %w[info success warning error].freeze

  belongs_to :user, optional: true

  validates :level, inclusion: { in: LEVELS }
  validates :source, :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end

  # Convenience: create + optionally push to Telegram / mobile (iOS + Android).
  # Pass apns_user to target a specific user's devices; nil = all devices.
  # The notification record is tied to apns_user so that user's unread count
  # drives the iOS app icon badge. The `apns:` flag means "send a mobile push";
  # it fans out to both APNs (iOS) and FCM (Android), each gated by the user's
  # per-platform preference. Pass `workspace:` to also honor that user's
  # per-workspace push opt-out (e.g. muting NY Kitchen alerts).
  def self.notify!(level:, source:, title:, body: nil, telegram: false, apns: false, apns_url: nil, apns_subtitle: nil, apns_user: nil, workspace: nil)
    notification = create!(level: level, source: source, title: title, body: body, user: apns_user, url: apns_url)
    TelegramNotifier.send_alert(notification) if telegram
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
