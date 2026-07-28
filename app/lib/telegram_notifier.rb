require "net/http"
require "json"

class TelegramNotifier
  ICONS = {
    "info" => "ℹ️",
    "success" => "✅",
    "warning" => "⚠️",
    "error" => "🚨"
  }.freeze

  # Global kill switch for ALL outbound Telegram pings. Set the Setting
  # "telegram.muted" to "true" to silence every telegram: true notification at
  # once; email and iOS push channels are unaffected (they don't route through
  # here). Toggle at runtime, no redeploy:
  #   Setting.set("telegram.muted", "true")   # off
  #   Setting.delete_key("telegram.muted")    # back on
  # Muted 2026-07-27 per owner: email + iOS cover failures, and the per-run
  # scrape/agent play-by-play pings were just noise.
  MUTE_KEY = "telegram.muted".freeze

  def self.muted?
    Setting.get(MUTE_KEY) == "true"
  end

  def self.send_alert(notification)
    return if muted?

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
