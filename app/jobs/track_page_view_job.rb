class TrackPageViewJob < ApplicationJob
  queue_as :default

  def perform(path:, ip_address:, user_agent:, referrer:, user_id:, session_id:)
    browser, os, device_type = parse_user_agent(user_agent)
    geo = lookup_geolocation(ip_address)

    PageView.create!(
      path: path,
      ip_address: ip_address,
      user_agent: user_agent,
      browser: browser,
      device_type: device_type,
      os: os,
      referrer: referrer,
      country: geo[:country],
      city: geo[:city],
      latitude: geo[:latitude],
      longitude: geo[:longitude],
      user_id: user_id,
      session_id: session_id
    )
  end

  private

  def parse_user_agent(ua)
    return [ "Unknown", "Unknown", "desktop" ] if ua.blank?

    # Browser detection
    browser = case ua
    when /Edg\//i then "Edge"
    when /OPR|Opera/i then "Opera"
    when /Chrome/i then "Chrome"
    when /Firefox/i then "Firefox"
    when /Safari/i then "Safari"
    else "Other"
    end

    # OS detection
    os = case ua
    when /Windows/i then "Windows"
    when /Macintosh|Mac OS/i then "macOS"
    when /Android/i then "Android"
    when /iPhone|iPad|iPod/i then "iOS"
    when /Linux/i then "Linux"
    else "Other"
    end

    # Device type detection
    device_type = case ua
    when /iPad|Tablet/i then "tablet"
    when /Mobile|iPhone|Android(?!.*\bChrome\/[.0-9]* (?!Mobile))/i then "mobile"
    else "desktop"
    end

    [ browser, os, device_type ]
  end

  def lookup_geolocation(ip_address)
    empty = { country: nil, city: nil, latitude: nil, longitude: nil }
    return empty if ip_address.blank?
    return empty if ip_address.match?(/\A(127\.|::1|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/i)

    cache_key = "geo:#{ip_address}"
    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      uri = URI("http://ip-api.com/json/#{ip_address}?fields=country,city,lat,lon,status")
      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        if data["status"] == "success"
          { country: data["country"], city: data["city"], latitude: data["lat"], longitude: data["lon"] }
        else
          empty
        end
      else
        empty
      end
    rescue StandardError
      empty
    end
  end
end
