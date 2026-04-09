require "net/http"
require "json"

class TelegramNotifier
  ICONS = {
    "info" => "ℹ️",
    "success" => "✅",
    "warning" => "⚠️",
    "error" => "🚨"
  }.freeze

  def self.send_alert(notification)
    token = ENV["TELEGRAM_BOT_TOKEN"]
    chat_id = ENV["TELEGRAM_CHAT_ID"]
    return unless token.present? && chat_id.present?

    icon = ICONS.fetch(notification.level, "•")
    text = "#{icon} *Agent44 Alert* — `#{notification.source}`\n\n*#{notification.title}*"
    text += "\n\n#{notification.body}" if notification.body.present?

    uri = URI("https://api.telegram.org/bot#{token}/sendMessage")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri)
    req["content-type"] = "application/json"
    req.body = { chat_id: chat_id, text: text, parse_mode: "Markdown" }.to_json

    response = http.request(req)
    Rails.logger.warn("Telegram alert failed (#{response.code}): #{response.body}") unless response.is_a?(Net::HTTPSuccess)
  rescue => e
    Rails.logger.error("TelegramNotifier error: #{e.message}")
  end
end
