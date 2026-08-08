# frozen_string_literal: true

require "openssl"

# Shared config for the Telegram webhook: where Telegram posts updates, the
# secret that proves a POST really came from Telegram, and which chat is
# allowed to run privileged commands.
#
# The endpoint is public (Telegram can't send an API token), so the only thing
# standing between the open internet and "deploy agent44" is the secret token
# Telegram echoes back in X-Telegram-Bot-Api-Secret-Token on every update.
module TelegramWebhook
  URL = "https://agent44labs.com/api/v1/telegram/webhook"

  # Derived from the bot token by default so there is no second secret to set
  # on Fly: setWebhook registers this value and Telegram sends it back on every
  # update. Set TELEGRAM_WEBHOOK_SECRET to pin it explicitly (rotating the bot
  # token rotates the derived secret, which is fine as long as both sides come
  # from the same deploy).
  def self.secret
    explicit = ENV["TELEGRAM_WEBHOOK_SECRET"]
    return explicit if explicit.present?

    bot_token = ENV["TELEGRAM_BOT_TOKEN"]
    return nil if bot_token.blank?

    OpenSSL::HMAC.hexdigest("SHA256", bot_token, "telegram-webhook")
  end

  # Fails closed: an update with no matching secret is not from our webhook
  # registration, and an unconfigured app has no legitimate caller at all.
  def self.valid_secret?(presented)
    expected = secret
    return false if expected.blank? || presented.blank?

    ActiveSupport::SecurityUtils.secure_compare(presented.to_s, expected)
  end

  # The owner's chat (same one TelegramNotifier alerts into). Anyone who finds
  # the bot's username can DM it, and Telegram will forward that message here
  # with a valid secret, so privileged commands check the chat too.
  def self.owner_chat?(chat_id)
    owner = ENV["TELEGRAM_CHAT_ID"]
    owner.present? && chat_id.present? && chat_id.to_s == owner.to_s
  end
end
