# Re-register the Telegram webhook on boot so deploys don't leave it blank.
# Runs in a background thread to avoid slowing down boot.
if Rails.env.production? && ENV["TELEGRAM_BOT_TOKEN"].present?
  Thread.new do
    sleep 5 # let the server finish binding first
    require "net/http"
    require "json"

    token = ENV["TELEGRAM_BOT_TOKEN"]
    webhook_url = "https://agent44labs.com/api/v1/telegram/webhook"

    uri = URI("https://api.telegram.org/bot#{token}/setWebhook")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = { url: webhook_url }.to_json

    res = http.request(req)
    Rails.logger.info("[TelegramWebhook] Registered webhook: #{res.body}")
  rescue => e
    Rails.logger.error("[TelegramWebhook] Failed to register webhook: #{e.message}")
  end
end
