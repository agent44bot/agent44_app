class Notification < ApplicationRecord
  LEVELS = %w[info success warning error].freeze

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

  # Convenience: create + optionally push to Telegram / APNs
  # Pass apns_user to target a specific user's iOS devices; nil = all devices.
  def self.notify!(level:, source:, title:, body: nil, telegram: false, apns: false, apns_url: nil, apns_subtitle: nil, apns_user: nil)
    notification = create!(level: level, source: source, title: title, body: body)
    TelegramNotifier.send_alert(notification) if telegram
    ApnsPusher.send_alert(notification, url: apns_url, subtitle: apns_subtitle, user: apns_user) if apns
    notification
  rescue => e
    Rails.logger.error("Notification.notify! failed: #{e.message}")
    nil
  end
end
