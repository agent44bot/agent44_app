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

  # Convenience: create + optionally push to Telegram
  def self.notify!(level:, source:, title:, body: nil, telegram: false)
    notification = create!(level: level, source: source, title: title, body: body)
    TelegramNotifier.send_alert(notification) if telegram
    notification
  rescue => e
    Rails.logger.error("Notification.notify! failed: #{e.message}")
    nil
  end
end
