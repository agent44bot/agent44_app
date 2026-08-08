# Re-register the Telegram webhook on boot so deploys don't leave it blank.
# Runs in a background thread to avoid slowing down boot.
if Rails.env.production? && ENV["TELEGRAM_BOT_TOKEN"].present?
  Thread.new do
    sleep 5 # let the server finish binding first
    require "net/http"
    require "json"

    token = ENV["TELEGRAM_BOT_TOKEN"]
    webhook_url = TelegramWebhook::URL

    uri = URI("https://api.telegram.org/bot#{token}/setWebhook")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    # secret_token is what the controller checks on every update; without it the
    # endpoint is open to anyone who guesses the URL.
    req.body = { url: webhook_url, secret_token: TelegramWebhook.secret }.compact.to_json

    res = http.request(req)
    Rails.logger.info("[TelegramWebhook] Registered webhook: #{res.body}")
  rescue => e
    Rails.logger.error("[TelegramWebhook] Failed to register webhook: #{e.message}")
  end
end
