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

  # force: true sends even while the global mute is on. For one-off alerts the
  # owner explicitly asked for (e.g. a read receipt on a specific notification),
  # as opposed to the per-run play-by-play the mute exists to silence.
  def self.send_alert(notification, force: false)
    return if muted? && !force

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
