require "net/http"

# Geolocates the display screen's IP (off the heartbeat request) and stores a
# short "City, ST" label the NYK hub shows next to the carousel-live indicator.
# This makes "Carousel live" tell the truth about WHERE the screen is: a stray
# heartbeat from someone's home laptop shows their city, not "at NY Kitchen".
class ResolveDisplayLocationJob < ApplicationJob
  queue_as :default

  # Same source as page-view geolocation (ip-api.com), cached per IP so a screen
  # pinging every 60s does at most one lookup a day. Failures are swallowed: a
  # missing city just falls back to no location on the card.
  def perform(ip)
    return if ip.blank?
    return if ip.match?(/\A(127\.|::1|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/i)

    city = Rails.cache.fetch("nyk_display_geo:#{ip}", expires_in: 24.hours) do
      uri = URI("http://ip-api.com/json/#{ip}?fields=status,city,region")
      res = Net::HTTP.get_response(uri)
      next nil unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body)
      next nil unless data["status"] == "success"

      [ data["city"], data["region"] ].reject(&:blank?).join(", ").presence
    rescue StandardError
      nil
    end

    Setting.set("nyk_display:city", city) if city.present?
  end
end
